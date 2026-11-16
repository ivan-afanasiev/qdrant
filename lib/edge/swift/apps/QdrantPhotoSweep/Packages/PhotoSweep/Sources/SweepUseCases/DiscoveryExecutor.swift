import Foundation
import SweepDomain

public struct DiscoveryConfiguration: Sendable {
    public var buffer: ReviewBufferPolicy
    /// Matches requested per neighborhood page; a shorter page ends the query.
    public var pageSize: Int

    public init(buffer: ReviewBufferPolicy = .default, pageSize: Int = 64) {
        self.buffer = buffer
        self.pageSize = max(1, pageSize)
    }
}

/// Foreground-only owner of lazy duplicate discovery. It keeps 2–3 ready groups by
/// expanding one connected component at a time from the newest unexamined photo,
/// checkpointing after every neighborhood query so interrupted work resumes.
public actor DiscoveryExecutor {
    public struct Dependencies: Sendable {
        public let vectorStores: any VectorStoreProviding
        public let assets: any AssetRepository
        public let discovery: any DiscoveryRepository
        public let progress: any DiscoveryProgressRepository
        public let review: any ReviewRepository
        public let workflow: any WorkflowStateRepository
        public let ids: any IDGenerating

        public init(
            vectorStores: any VectorStoreProviding,
            assets: any AssetRepository,
            discovery: any DiscoveryRepository,
            progress: any DiscoveryProgressRepository,
            review: any ReviewRepository,
            workflow: any WorkflowStateRepository,
            ids: any IDGenerating
        ) {
            self.vectorStores = vectorStores
            self.assets = assets
            self.discovery = discovery
            self.progress = progress
            self.review = review
            self.workflow = workflow
            self.ids = ids
        }
    }

    private let dependencies: Dependencies
    private let configuration: DiscoveryConfiguration
    private let broadcast = StatusBroadcast(DiscoveryUpdate(revision: DiscoveryRevision(0), status: .waitingForInitialPass))
    private var presence: AppPresence = .foreground
    private var runTask: Task<Void, Never>?
    private var refillRequested = false

    public init(dependencies: Dependencies, configuration: DiscoveryConfiguration = DiscoveryConfiguration()) {
        self.dependencies = dependencies
        self.configuration = configuration
    }

    // MARK: - Observation

    public nonisolated func updates() -> AsyncStream<DiscoveryUpdate> {
        broadcast.stream()
    }

    public nonisolated var current: DiscoveryUpdate {
        broadcast.value
    }

    // MARK: - Control

    /// Fills the review buffer if possible. Call after review/skip, on activation and when
    /// newly committed vectors become eligible. Never runs in the background.
    public func requestRefill() {
        if runTask != nil {
            refillRequested = true
            return
        }
        runTask = Task { await self.refillLoop() }
    }

    /// Background entry suspends discovery at the last checkpoint; foreground entry resumes it.
    public func setPresence(_ presence: AppPresence) async {
        self.presence = presence
        switch presence {
        case .background:
            await stopRunning()
            broadcast.send(DiscoveryUpdate(revision: broadcast.value.revision, status: .suspended))
        case .foreground:
            requestRefill()
        }
    }

    /// Threshold change or rescan: retires current groups, review order and skip deferrals,
    /// then discovers again from the newest photo using the existing vectors.
    @discardableResult
    public func beginNewRevision() async throws(PersistenceError) -> DiscoveryRevision {
        await stopRunning()
        guard let state = try await dependencies.workflow.modifyWorkflowState({ $0.discoveryRevision = $0.discoveryRevision.next() }) else {
            throw .notFound("Workflow state")
        }
        try await dependencies.review.retireGroups(before: state.discoveryRevision)
        broadcast.send(DiscoveryUpdate(revision: state.discoveryRevision, status: .searching))
        requestRefill()
        return state.discoveryRevision
    }

    /// Stops any running refill at its last checkpoint, for example before a reset.
    public func stop() async {
        await stopRunning()
    }

    public func waitUntilIdle() async {
        while let runTask {
            await runTask.value
        }
    }

    private func stopRunning() async {
        refillRequested = false
        guard let runTask else { return }
        runTask.cancel()
        await runTask.value
    }

    // MARK: - Refill

    private func refillLoop() async {
        repeat {
            refillRequested = false
            await refillOnce()
        } while refillRequested && !Task.isCancelled
        runTask = nil
    }

    private func refillOnce() async {
        var revision = broadcast.value.revision
        do {
            guard let state = try await dependencies.workflow.loadWorkflowState() else {
                publish(revision, .waitingForInitialPass)
                return
            }
            revision = state.discoveryRevision
            guard state.gate.isOpen, let compatibility = state.indexCompatibility else {
                publish(revision, .waitingForInitialPass)
                return
            }
            guard presence == .foreground else {
                publish(revision, .suspended)
                return
            }
            let store: any VectorStoring
            do {
                store = try await dependencies.vectorStores.store(for: state.indexGeneration, dimensions: compatibility.dimensions)
            } catch {
                publish(revision, .failed("Vector store: \(error)"))
                return
            }
            try await fill(state: state, store: store)
        } catch is CancellationError {
            if presence == .background {
                publish(revision, .suspended)
            }
        } catch {
            publish(revision, .failed(String(describing: error)))
        }
    }

    /// Discovers components until the buffer is full or no eligible seed remains.
    private func fill(state: WorkflowState, store: any VectorStoring) async throws {
        let revision = state.discoveryRevision
        while true {
            try Task.checkCancellation()
            let progress = try await dependencies.progress.discoveryProgress(for: revision) ?? DiscoveryProgress(revision: revision)
            let readyCount = try await dependencies.review.reviewQueue(for: revision).readyCount

            var expansion: ComponentExpansion
            if let restored = progress.expansion.flatMap(ComponentExpansion.init(restoring:)),
               restored.threshold == state.threshold, restored.scope == state.scope, restored.generation == state.indexGeneration {
                // An interrupted component is always finished, even if the buffer filled meanwhile.
                expansion = restored
            } else {
                if configuration.buffer.isFull(readyCount: readyCount) {
                    publish(revision, .bufferReady)
                    return
                }
                guard let seed = try await dependencies.discovery.nextSeed(revision: revision, scope: state.scope, generation: state.indexGeneration) else {
                    var exhausted = progress
                    exhausted.isSeedCursorExhausted = true
                    exhausted.expansion = nil
                    try await dependencies.progress.saveDiscoveryProgress(exhausted)
                    publish(revision, status(readyCount: readyCount, exhausted: true))
                    return
                }
                guard let started = ComponentExpansion(
                    seed: seed.id, seedCreationDate: seed.creationDate, scope: state.scope,
                    threshold: state.threshold, generation: state.indexGeneration
                ) else {
                    try await dependencies.discovery.completeComponent(members: [seed.id], outcome: .discarded, progress: DiscoveryProgress(revision: revision, seedCursor: seed.id))
                    continue
                }
                expansion = started
            }
            publish(revision, .searching)
            try await expand(&expansion, revision: revision, state: state, store: store)
            try await finish(expansion, revision: revision)
        }
    }

    /// Queries every frontier member's complete neighborhood page by page, checkpointing after each.
    private func expand(_ expansion: inout ComponentExpansion, revision: DiscoveryRevision, state: WorkflowState, store: any VectorStoring) async throws {
        let filter = VectorSearchFilter(scope: state.scope)
        while let query = expansion.nextQuery {
            try Task.checkCancellation()
            let record = try await dependencies.assets.assets([query])[query]
            let vector = try await record.asyncFlatMap { try await store.vector(id: $0.pointID.storeKey) }
            guard let vector else {
                // No stored vector (removed meanwhile): this member contributes no neighbors.
                try expansion.absorb([], for: query, isLastPage: true)
                continue
            }
            var offset = 0
            var isLastPage = false
            while !isLastPage {
                let page = try await store.searchPage(
                    vector: vector, threshold: state.threshold.value, filter: filter,
                    offset: offset, limit: configuration.pageSize
                )
                isLastPage = page.count < configuration.pageSize
                offset += page.count
                let candidates = page.compactMap { result in
                    VectorPayload.decode(result.payloadJson).map { ($0.assetID, result.score) }
                }
                // Eligibility and dates come from committed metadata, never from point existence.
                let records = try await dependencies.assets.assets(candidates.map(\.0))
                let eligible = Set(records.values.filter { $0.storedVector?.generation == state.indexGeneration }.map(\.id))
                let neighbors = candidates.compactMap { asset, score in
                    records[asset].map { Neighbor(asset: asset, creationDate: $0.creationDate, score: score) }
                }
                try expansion.absorb(neighbors, for: query, isLastPage: isLastPage) { eligible.contains($0) }
            }
            try await dependencies.progress.saveDiscoveryProgress(
                DiscoveryProgress(revision: revision, seedCursor: expansion.seed, expansion: expansion.snapshot)
            )
        }
    }

    /// Publishes, merges or discards a fully expanded component in one transaction.
    private func finish(_ expansion: ComponentExpansion, revision: DiscoveryRevision) async throws {
        let members = expansion.snapshot.visited
        let memberSet = Set(members)
        let done = DiscoveryProgress(revision: revision, seedCursor: expansion.seed)
        let outcome: ComponentOutcome
        let isSuppressed = expansion.isGroup
            ? try await dependencies.review.isSuppressed(memberSet, revision: revision)
            : false
        if !expansion.isGroup || isSuppressed {
            // Single photos have nothing to review; overlaps with reviewed groups stay suppressed.
            outcome = .discarded
        } else {
            let pending = try await dependencies.discovery.pendingGroups(containing: memberSet, revision: revision)
            if pending.count == 1, let existing = pending.first {
                outcome = .merged(into: existing, members: members)
            } else {
                let group = ReviewGroupSnapshot(
                    id: GroupID(dependencies.ids.makeUUID()),
                    revision: MembershipRevision(1),
                    discoveryRevision: revision,
                    members: members
                )
                outcome = .published(group, derivedFrom: pending)
            }
        }
        try await dependencies.discovery.completeComponent(members: members, outcome: outcome, progress: done)
    }

    private func status(readyCount: Int, exhausted: Bool) -> DiscoveryStatus {
        DiscoveryPolicy.status(
            DiscoveryInputs(isInitialGateOpen: true, presence: presence, readyCount: readyCount, isSeedCursorExhausted: exhausted),
            buffer: configuration.buffer
        )
    }

    private func publish(_ revision: DiscoveryRevision, _ status: DiscoveryStatus) {
        let update = DiscoveryUpdate(revision: revision, status: status)
        if broadcast.value != update {
            broadcast.send(update)
        }
    }
}

private extension Optional {
    func asyncFlatMap<T>(_ transform: (Wrapped) async throws -> T?) async throws -> T? {
        guard let value = self else { return nil }
        return try await transform(value)
    }
}
