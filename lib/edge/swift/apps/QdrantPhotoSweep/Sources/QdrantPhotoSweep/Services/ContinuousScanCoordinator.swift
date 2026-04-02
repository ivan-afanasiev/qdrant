import BackgroundTasks
import Foundation

@Observable
@MainActor
final class ContinuousScanCoordinator {
    static let taskIdentifier = "com.qdrant.edge.PhotoSweep.continuousScan"

    enum Phase: Equatable {
        case idle
        case scanning(processed: Int, total: Int)
        case grouping(progress: Double)
        case completed(groups: [DuplicateGroup])
        case failed(AppError)
        case cancelled
    }

    private(set) var phase: Phase = .idle
    private var workTask: Task<Void, Never>?
    private var bgTaskHandle: AnyObject?

    var scanProgress: Double {
        switch phase {
        case .scanning(let processed, let total) where total > 0:
            Double(processed) / Double(total)
        case .grouping(let progress):
            progress
        case .completed:
            1.0
        default:
            0
        }
    }

    var isActive: Bool {
        switch phase {
        case .scanning, .grouping: true
        default: false
        }
    }

    // MARK: - Registration (iOS 26+ only)

    nonisolated static func register() {
        guard #available(iOS 26.0, *) else { return }
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: taskIdentifier,
            using: nil
        ) { task in
            guard let continuedTask = task as? BGContinuedProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor in
                ContinuousScanCoordinator.attachBgTask(continuedTask)
            }
        }
    }

    @available(iOS 26.0, *)
    private static var activeCoordinator: ContinuousScanCoordinator?

    @available(iOS 26.0, *)
    private static func attachBgTask(_ task: BGContinuedProcessingTask) {
        if let coordinator = activeCoordinator {
            coordinator.bgTaskHandle = task
            task.progress.totalUnitCount = 100
            task.expirationHandler = { [weak coordinator] in
                coordinator?.workTask?.cancel()
            }
        } else {
            task.setTaskCompleted(success: false)
        }
    }

    // MARK: - Full pipeline: scan + detect

    func startFullPipeline(
        dateRange: DateRange,
        resumeSessionId: UUID?,
        deps: Dependencies
    ) {
        guard !isActive else { return }
        phase = .scanning(processed: 0, total: 0)

        requestBackgroundSupport()
        runFullPipeline(dateRange: dateRange, resumeSessionId: resumeSessionId, deps: deps)
    }

    // MARK: - Standalone grouping

    func startGrouping(deps: Dependencies, sessionId: UUID? = nil) {
        guard !isActive else { return }
        phase = .grouping(progress: 0)

        requestBackgroundSupport()
        runGrouping(deps: deps, sessionId: sessionId)
    }

    func cancel() {
        workTask?.cancel()
        workTask = nil
        completeBgTask(success: false)
        clearActiveCoordinator()
        phase = .cancelled
    }

    // MARK: - Background support (optional, iOS 26+)

    private func requestBackgroundSupport() {
        guard #available(iOS 26.0, *) else { return }
        Self.activeCoordinator = self
        do {
            let request = BGContinuedProcessingTaskRequest(
                identifier: Self.taskIdentifier,
                title: String(localized: "continuousTask.scan.title"),
                subtitle: String(localized: "continuousTask.scan.subtitle")
            )
            try BGTaskScheduler.shared.submit(request)
        } catch {
            Self.activeCoordinator = nil
        }
    }

    private func clearActiveCoordinator() {
        guard #available(iOS 26.0, *) else { return }
        Self.activeCoordinator = nil
    }

    // MARK: - BGTask helpers

    private func updateBgProgress(_ units: Int64) {
        guard #available(iOS 26.0, *),
              let task = bgTaskHandle as? BGContinuedProcessingTask else { return }
        task.progress.completedUnitCount = units
    }

    private func updateBgTitle(_ title: String, subtitle: String) {
        guard #available(iOS 26.0, *),
              let task = bgTaskHandle as? BGContinuedProcessingTask else { return }
        task.updateTitle(title, subtitle: subtitle)
    }

    private func completeBgTask(success: Bool) {
        guard #available(iOS 26.0, *),
              let task = bgTaskHandle as? BGContinuedProcessingTask else { return }
        task.setTaskCompleted(success: success)
        bgTaskHandle = nil
    }

    // MARK: - Full pipeline execution

    private func runFullPipeline(
        dateRange: DateRange,
        resumeSessionId: UUID?,
        deps: Dependencies
    ) {
        workTask?.cancel()
        workTask = Task { [weak self] in
            guard let self else { return }

            let scanState = ScanState()
            let scanObservation = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(150))
                    guard let self else { return }
                    let status = scanState.status
                    switch status {
                    case .scanning(let processed, let total):
                        self.phase = .scanning(processed: processed, total: total)
                        if total > 0 {
                            self.updateBgProgress(Int64(Double(processed) / Double(total) * 50))
                        }
                    default:
                        break
                    }
                }
            }

            let pipeline = ScanPipeline(
                photoLibrary: deps.photoLibrary,
                embeddingService: deps.embeddingService,
                vectorStore: deps.vectorStore,
                scanStore: deps.scanStore,
                configureDimensions: { dims in
                    if let store = deps.vectorStore as? QdrantVectorStore {
                        await store.updateDimensions(dims)
                    }
                }
            )

            await pipeline.run(
                dateRange: dateRange,
                state: scanState,
                resumeSessionId: resumeSessionId
            )

            scanObservation.cancel()

            if Task.isCancelled {
                try? await deps.scanStore.interruptActiveSessions()
                await MainActor.run { self.phase = .cancelled }
                self.completeBgTask(success: false)
                self.clearActiveCoordinator()
                return
            }

            let scanStatus = await scanState.status
            switch scanStatus {
            case .failed(let error):
                await MainActor.run { self.phase = .failed(error) }
                self.completeBgTask(success: false)
                self.clearActiveCoordinator()
                return
            case .cancelled:
                await MainActor.run { self.phase = .cancelled }
                self.completeBgTask(success: false)
                self.clearActiveCoordinator()
                return
            default:
                break
            }

            self.updateBgProgress(50)
            self.updateBgTitle(
                String(localized: "continuousTask.grouping.title"),
                subtitle: String(localized: "continuousTask.grouping.subtitle")
            )

            await MainActor.run { self.phase = .grouping(progress: 0) }

            let sessionDTO = try? await deps.scanStore.latestCompletedSession()
            let groups = await self.performGrouping(
                deps: deps,
                sessionId: sessionDTO?.id,
                progressBase: 50
            )

            if Task.isCancelled {
                try? await deps.scanStore.interruptActiveSessions()
                await MainActor.run { self.phase = .cancelled }
                self.completeBgTask(success: false)
                self.clearActiveCoordinator()
                return
            }

            self.updateBgProgress(100)
            await MainActor.run { self.phase = .completed(groups: groups) }
            self.completeBgTask(success: true)
            self.clearActiveCoordinator()
        }
    }

    // MARK: - Standalone grouping execution

    private func runGrouping(
        deps: Dependencies,
        sessionId: UUID?
    ) {
        workTask?.cancel()
        workTask = Task { [weak self] in
            guard let self else { return }

            let resolvedSessionId: UUID?
            if let sid = sessionId {
                resolvedSessionId = sid
            } else {
                resolvedSessionId = try? await deps.scanStore.latestCompletedSession()?.id
            }

            let groups = await self.performGrouping(
                deps: deps,
                sessionId: resolvedSessionId,
                progressBase: 0
            )

            if Task.isCancelled {
                try? await deps.scanStore.interruptActiveSessions()
                await MainActor.run { self.phase = .cancelled }
                self.completeBgTask(success: false)
                self.clearActiveCoordinator()
                return
            }

            self.updateBgProgress(100)
            await MainActor.run { self.phase = .completed(groups: groups) }
            self.completeBgTask(success: true)
            self.clearActiveCoordinator()
        }
    }

    // MARK: - Shared grouping logic

    private func performGrouping(
        deps: Dependencies,
        sessionId: UUID?,
        progressBase: Int64
    ) async -> [DuplicateGroup] {
        if let sessionId {
            try? await deps.scanStore.updateSessionStatus(sessionId, status: .grouping, indexedPhotos: nil)
        }

        let detectionState = DuplicateDetectionState()
        let threshold = deps.settings.similarityThreshold

        let observation = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                guard let self else { return }
                if case .analyzing(let p) = detectionState.status {
                    self.phase = .grouping(progress: p)
                    let remaining = 100 - progressBase
                    self.updateBgProgress(progressBase + Int64(p * Double(remaining)))
                }
            }
        }

        await detectionState.findDuplicates(
            vectorStore: deps.vectorStore,
            threshold: threshold,
            scanStore: deps.scanStore
        )

        observation.cancel()

        if Task.isCancelled {
            if let sessionId {
                try? await deps.scanStore.updateSessionStatus(sessionId, status: .groupingInterrupted, indexedPhotos: nil)
            }
            return []
        }

        if let sessionId {
            try? await deps.scanStore.updateSessionStatus(sessionId, status: .completed, indexedPhotos: nil)
        }

        switch await detectionState.status {
        case .complete(let groups): return groups
        default: return []
        }
    }
}
