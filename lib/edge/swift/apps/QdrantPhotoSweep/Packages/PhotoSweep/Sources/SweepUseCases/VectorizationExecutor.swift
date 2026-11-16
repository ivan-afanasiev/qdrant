import Foundation
import SweepDomain

public struct VectorizationConfiguration: Sendable {
    public var thumbnailPixels: Int
    public var batchSize: Int
    /// Stops the pass when this many photos in a row are set aside, which indicates a
    /// systemic problem (for example a broken model) rather than individual bad photos.
    public var maxConsecutiveDeferrals: Int
    public var defaultScope: DateRange
    public var defaultThreshold: SimilarityThreshold
    public var retryPolicy: RetryPolicy
    /// Clock used to resolve rolling date presets.
    public var now: @Sendable () -> Date

    /// Batch, breaker and retry values are provisional until measured on devices.
    public init(
        thumbnailPixels: Int = 224,
        batchSize: Int = 16,
        maxConsecutiveDeferrals: Int = 10,
        defaultScope: DateRange = DateRange(start: .distantPast, end: .distantFuture),
        defaultThreshold: SimilarityThreshold = .standard,
        retryPolicy: RetryPolicy = .default,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.thumbnailPixels = thumbnailPixels
        self.batchSize = max(1, batchSize)
        self.maxConsecutiveDeferrals = max(1, maxConsecutiveDeferrals)
        self.defaultScope = defaultScope
        self.defaultThreshold = defaultThreshold
        self.retryPolicy = retryPolicy
        self.now = now
    }

    /// Identifies how thumbnails are produced; part of vector compatibility.
    public var preprocessing: String { "thumbnail-\(thumbnailPixels)-fast" }
}

public enum VectorizationTriggerOutcome: Equatable, Sendable {
    case started
    /// A pass is already running; another pass follows it to pick up new work.
    case queued
    case blockedByManualPause
    case failed(VectorizationStopReason)
}

/// The single app-owned owner of vectorization passes. Foreground triggers, Pause, Resume,
/// Retry and system interruption all go through this actor; observers subscribe to status
/// and never control the pass by unsubscribing.
public actor VectorizationExecutor {
    public struct Dependencies: Sendable {
        public let library: any PhotoLibraryProviding
        public let embedder: any EmbeddingProviding
        public let model: any EmbeddingModelDescribing
        public let vectorStores: any VectorStoreProviding
        public let assets: any AssetRepository
        public let passes: any VectorizationPassRepository
        public let workflow: any WorkflowStateRepository
        public let journal: any VectorWriteJournaling
        public let ids: any IDGenerating
        public let sleeper: any Sleeper

        public init(
            library: any PhotoLibraryProviding,
            embedder: any EmbeddingProviding,
            model: any EmbeddingModelDescribing,
            vectorStores: any VectorStoreProviding,
            assets: any AssetRepository,
            passes: any VectorizationPassRepository,
            workflow: any WorkflowStateRepository,
            journal: any VectorWriteJournaling,
            ids: any IDGenerating,
            sleeper: any Sleeper
        ) {
            self.library = library
            self.embedder = embedder
            self.model = model
            self.vectorStores = vectorStores
            self.assets = assets
            self.passes = passes
            self.workflow = workflow
            self.journal = journal
            self.ids = ids
            self.sleeper = sleeper
        }
    }

    private enum StopReason {
        case userPause
        case system
    }

    private struct PassStopped: Error {
        let reason: VectorizationStopReason
    }

    private let dependencies: Dependencies
    private let configuration: VectorizationConfiguration
    private let broadcast = StatusBroadcast<VectorizationStatus>(.idle)
    private let completedPasses = StatusBroadcast<CompletedPass?>(nil)
    private var runTask: Task<Void, Never>?
    private var changeTask: Task<Void, Never>?
    private var stopReason: StopReason?
    private var rerunRequested = false
    /// Authoritative in memory so a pause cannot be lost between asynchronous saves.
    private var isManuallyPaused: Bool?
    private var progress = VectorizationProgress(total: 0, vectorized: 0, deferred: 0)

    public init(dependencies: Dependencies, configuration: VectorizationConfiguration = VectorizationConfiguration()) {
        self.dependencies = dependencies
        self.configuration = configuration
    }

    // MARK: - Observation

    public nonisolated func statusUpdates() -> AsyncStream<VectorizationStatus> {
        broadcast.stream()
    }

    public nonisolated var status: VectorizationStatus {
        broadcast.value
    }

    /// The most recently completed pass that processed photos, for readiness notifications.
    /// Empty follow-up passes do not replace it, so they cannot hide a pass worth announcing.
    public nonisolated var lastCompletedPass: CompletedPass? {
        completedPasses.value
    }

    /// Re-runs vectorization whenever the photo library reports changes.
    public func startObservingLibraryChanges(_ source: any PhotoLibraryChangeObserving) {
        changeTask?.cancel()
        let changes = source.libraryChanges()
        changeTask = Task { [weak self] in
            for await _ in changes {
                await self?.handle(.automaticForeground)
            }
        }
    }

    public func stopObservingLibraryChanges() {
        changeTask?.cancel()
        changeTask = nil
    }

    // MARK: - Control

    @discardableResult
    public func handle(_ trigger: VectorizationTrigger) async -> VectorizationTriggerOutcome {
        let state: WorkflowState
        do {
            state = try await loadOrCreateWorkflowState()
        } catch {
            let reason = VectorizationStopReason.systemic("Metadata store: \(error)")
            broadcast.send(.failed(reason, progress))
            return .failed(reason)
        }
        let current = PauseState(isPausedByUser: isManuallyPaused ?? state.pause.isPausedByUser)
        switch PausePolicy.decide(trigger, current: current) {
        case .blockedByManualPause:
            isManuallyPaused = true
            if runTask == nil {
                broadcast.send(.pausedByUser(progress))
            }
            return .blockedByManualPause
        case .run(let pause):
            if pause != current {
                isManuallyPaused = pause.isPausedByUser
                try? await persistPause()
            }
        }
        // No suspension between this check and starting the task.
        if runTask != nil {
            rerunRequested = true
            return .queued
        }
        stopReason = nil
        runTask = Task { await self.runPasses() }
        return .started
    }

    /// Manual Pause: checkpoints at a safe boundary and blocks automatic and background
    /// work until Resume or the next app opening.
    public func pause() async {
        isManuallyPaused = true
        try? await persistPause()
        if let runTask {
            stopReason = .userPause
            runTask.cancel()
            await runTask.value
        } else {
            broadcast.send(.pausedByUser(progress))
        }
    }

    public func resume() async {
        await handle(.userResume)
    }

    /// Retry is offered after a failure or an interruption.
    public func retry() async {
        switch broadcast.value {
        case .failed, .interrupted: await handle(.userRetry)
        default: break
        }
    }

    /// System interruption (expiration, termination): stops at a safe boundary without
    /// setting manual pause; the next trigger resumes the checkpointed pass.
    public func interrupt() async {
        guard let runTask else { return }
        stopReason = .system
        runTask.cancel()
        await runTask.value
    }

    /// Waits until no pass is running, including queued follow-up passes.
    public func waitUntilIdle() async {
        while let runTask {
            await runTask.value
        }
    }

    // MARK: - Passes

    private func runPasses() async {
        repeat {
            rerunRequested = false
            let completed = await runOnePass()
            guard completed, rerunRequested, !Task.isCancelled else { break }
        } while true
        runTask = nil
    }

    /// Returns true when the pass completed.
    private func runOnePass() async -> Bool {
        do {
            try await performPass()
            return true
        } catch let stopped as PassStopped {
            broadcast.send(.failed(stopped.reason, progress))
        } catch {
            // Cancellation: the pass is checkpointed after every batch.
            broadcast.send(stopReason == .userPause ? .pausedByUser(progress) : .interrupted(progress))
        }
        return false
    }

    private func performPass() async throws {
        let library = dependencies.library
        let retry = RetryRunner(policy: configuration.retryPolicy, sleeper: dependencies.sleeper)

        try await stopOnFailure { () async throws(VectorizationFailure) in
            do throws(AdapterError) {
                try await library.requestAuthorization()
            } catch {
                throw ReconcilePhotoLibrary.classify(error)
            }
        }
        let (state, compatibility) = try await prepareIndex()
        let store = try await stopOnFailure { () async throws(VectorizationFailure) -> any VectorStoring in
            do {
                return try await dependencies.vectorStores.store(for: state.indexGeneration, dimensions: compatibility.dimensions)
            } catch {
                throw .systemic("Vector store: \(error)")
            }
        }
        let reconciled = try await stopOnFailure { () async throws(VectorizationFailure) in
            try await ReconcilePhotoLibrary(library: library, assets: dependencies.assets).execute(scope: state.scope)
        }
        try Task.checkCancellation()

        var pass = try await selectPass(state: state, compatibility: compatibility, records: reconciled.records)
        progress = pass.progress
        broadcast.send(.running(progress))

        let records = Dictionary(reconciled.records.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let vectorizer = VectorizePhoto(library: library, embedder: dependencies.embedder, thumbnailPixels: configuration.thumbnailPixels)
        let writer = VectorWriteTransaction(journal: dependencies.journal, vectorStore: store, ids: dependencies.ids)
        var consecutiveDeferrals = 0

        let pending = pass.pendingAssets
        for start in stride(from: 0, to: pending.count, by: configuration.batchSize) {
            try Task.checkCancellation()
            var items: [VectorWriteItem] = []
            var deferrals: [AssetID: DeferralReason] = [:]
            var stop: VectorizationStopReason?

            for id in pending[start..<min(start + configuration.batchSize, pending.count)] {
                guard stop == nil else { break }
                try Task.checkCancellation()
                guard let photo = reconciled.photos[id], let record = records[id] else {
                    // No longer in the library scope (removed or access reduced).
                    deferrals[id] = .unavailable("Not available in the photo library")
                    continue
                }
                let outcome = try await retry.run { () async throws(VectorizationFailure) -> [Float] in
                    try await vectorizer.execute(photo, expectedDimensions: compatibility.dimensions)
                }
                switch outcome {
                case .succeeded(let vector, _):
                    consecutiveDeferrals = 0
                    items.append(VectorWriteItem(
                        intent: VectorWriteIntent(
                            assetID: id, pointID: record.pointID, contentRevision: record.contentRevision,
                            compatibility: compatibility, generation: state.indexGeneration
                        ),
                        vector: vector,
                        payloadJson: VectorPayload(asset: id, creationDate: photo.creationDate).json
                    ))
                case .deferred(let reason, _):
                    deferrals[id] = reason
                    consecutiveDeferrals += 1
                    if consecutiveDeferrals >= configuration.maxConsecutiveDeferrals {
                        stop = .systemic("\(consecutiveDeferrals) photos in a row could not be processed")
                    }
                case .stopped(let reason, _):
                    stop = reason
                }
            }

            // Checkpoint whatever this batch produced before acting on a stop.
            if !deferrals.isEmpty {
                try await stopOnFailure { () async throws(VectorizationFailure) in
                    do {
                        try await dependencies.passes.recordDeferred(deferrals, pass: pass.id)
                    } catch {
                        throw .systemic("Metadata store: \(error)")
                    }
                }
                for (id, reason) in deferrals {
                    pass.record(.deferred(reason), for: id)
                }
            }
            if !items.isEmpty {
                let batch = items
                let passID = pass.id
                let written = try await retry.run { () async throws(VectorizationFailure) in
                    do throws(VectorWriteError) {
                        try await writer.write(batch, pass: passID)
                    } catch {
                        throw error.failure
                    }
                }
                if case .stopped(let reason, _) = written {
                    stop = stop ?? reason
                } else {
                    for item in items {
                        pass.record(.vectorized, for: item.intent.assetID)
                    }
                }
            }
            progress = pass.progress
            if let stop {
                throw PassStopped(reason: stop)
            }
            broadcast.send(.running(progress))
        }

        try await finish(pass)
    }

    /// Loads workflow state and switches to a new index generation if the model changed.
    private func prepareIndex() async throws -> (WorkflowState, EmbeddingCompatibility) {
        let descriptor = try await stopOnFailure { () async throws(VectorizationFailure) in
            do {
                return try await dependencies.model.modelDescriptor()
            } catch {
                throw .systemic("Embedding model: \(error)")
            }
        }
        let compatibility = descriptor.compatibility(preprocessing: configuration.preprocessing)
        let today = configuration.now()
        let state = try await updateWorkflow { state in
            // Rolling date presets are resolved again for every pass.
            state.scope = state.datePreset.range(endingAt: today)
            guard state.indexCompatibility != compatibility else { return }
            if state.indexCompatibility != nil {
                // Recoverable generation transition: old vectors stay untouched until the new
                // generation is recorded, then stop being reused and are cleaned up.
                state.indexGeneration = state.indexGeneration.next()
                state.gate = InitialPassGate()
            }
            state.indexCompatibility = compatibility
        }
        await dependencies.vectorStores.removeStores(olderThan: state.indexGeneration)
        return (state, compatibility)
    }

    /// Resumes a checkpointed pass for the same scope, or starts a new one whose work set
    /// contains only photos without a reusable vector.
    private func selectPass(state: WorkflowState, compatibility: EmbeddingCompatibility, records: [AssetRecord]) async throws -> VectorizationPass {
        try await stopOnFailure { () async throws(VectorizationFailure) -> VectorizationPass in
            do {
                if let active = try await dependencies.passes.activePass(), active.scope == state.scope {
                    let isAwaited = state.gate.state == .awaitingInitialPass(active.id)
                    if active.kind == .incremental || isAwaited || state.gate.isOpen {
                        return active
                    }
                }
                let work = records.filter {
                    VectorReusePolicy.decide(
                        existing: $0.storedVector, currentRevision: $0.contentRevision,
                        compatibility: compatibility, generation: state.indexGeneration
                    ) != .reuse
                }.map(\.id)
                let pass = VectorizationPass(
                    id: VectorizationPassID(dependencies.ids.makeUUID()),
                    kind: state.gate.isOpen ? .incremental : .initial,
                    scope: state.scope,
                    workSet: work
                )
                if pass.kind == .initial {
                    _ = try await updateWorkflowState { $0.gate.beginInitialPass(pass.id) }
                }
                try await dependencies.passes.beginPass(pass)
                return pass
            } catch {
                throw .systemic("Metadata store: \(error)")
            }
        }
    }

    private func finish(_ pass: VectorizationPass) async throws {
        try await stopOnFailure { () async throws(VectorizationFailure) in
            do {
                _ = try await updateWorkflowState { $0.gate.passFinished(pass) }
                try await dependencies.passes.finishPass(pass.id)
            } catch {
                throw .systemic("Metadata store: \(error)")
            }
        }
        progress = pass.progress
        let completed = CompletedPass(id: pass.id, kind: pass.kind, progress: pass.progress)
        if completed.didWork {
            completedPasses.send(completed)
        }
        broadcast.send(.completed(deferredCount: pass.progress.deferred))
    }

    // MARK: - Workflow state

    private func loadOrCreateWorkflowState() async throws(PersistenceError) -> WorkflowState {
        if let state = try await dependencies.workflow.loadWorkflowState() {
            return state
        }
        let state = WorkflowState(
            scope: configuration.defaultScope,
            threshold: configuration.defaultThreshold,
            pause: .none,
            gate: InitialPassGate(),
            discoveryRevision: DiscoveryRevision(1),
            indexGeneration: IndexGeneration(1)
        )
        try await dependencies.workflow.saveWorkflowState(state)
        return state
    }

    /// Applies `change` atomically in the store, always keeping the in-memory pause, so fields
    /// owned by discovery or settings are never overwritten with stale values.
    private func updateWorkflowState(_ change: @Sendable (inout WorkflowState) -> Void) async throws(PersistenceError) -> WorkflowState {
        _ = try await loadOrCreateWorkflowState()
        let pause = isManuallyPaused.map { PauseState(isPausedByUser: $0) }
        let updated = try await dependencies.workflow.modifyWorkflowState { state in
            change(&state)
            if let pause {
                state.pause = pause
            }
        }
        guard let updated else { throw .notFound("Workflow state") }
        return updated
    }

    private func updateWorkflow(_ change: @Sendable (inout WorkflowState) -> Void) async throws -> WorkflowState {
        try await stopOnFailure { () async throws(VectorizationFailure) -> WorkflowState in
            do {
                return try await updateWorkflowState(change)
            } catch {
                throw .systemic("Metadata store: \(error)")
            }
        }
    }

    private func persistPause() async throws(PersistenceError) {
        _ = try await updateWorkflowState { _ in }
    }

    // MARK: - Helpers

    /// Converts a classified failure into a pass stop. Per-photo retries happen elsewhere.
    private func stopOnFailure<T>(_ body: () async throws(VectorizationFailure) -> T) async throws -> T {
        do {
            return try await body()
        } catch {
            switch error {
            case .authorization: throw PassStopped(reason: .authorization)
            case .incompatibleEmbedding(let message): throw PassStopped(reason: .incompatibleEmbedding(message))
            case .systemic(let message), .transient(let message), .assetUnavailable(let message):
                throw PassStopped(reason: .systemic(message))
            }
        }
    }

}
