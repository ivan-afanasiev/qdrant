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

    // MARK: - Registration

    nonisolated static func register() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: taskIdentifier,
            using: nil
        ) { task in
            guard let continuedTask = task as? BGContinuedProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor in
                PendingContinuousWork.shared.start(continuedTask)
            }
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

        submitOrFallback { [weak self] bgTask in
            self?.runFullPipeline(
                dateRange: dateRange,
                resumeSessionId: resumeSessionId,
                deps: deps,
                bgTask: bgTask
            )
        }
    }

    // MARK: - Standalone grouping

    func startGrouping(deps: Dependencies, sessionId: UUID? = nil) {
        guard !isActive else { return }
        phase = .grouping(progress: 0)

        submitOrFallback { [weak self] bgTask in
            self?.runGrouping(deps: deps, sessionId: sessionId, bgTask: bgTask)
        }
    }

    func cancel() {
        workTask?.cancel()
        workTask = nil
        phase = .cancelled
    }

    // MARK: - BGTask submission with fallback

    private func submitOrFallback(work: @escaping @MainActor (BGContinuedProcessingTask?) -> Void) {
        let pendingWork = PendingContinuousWork.shared
        pendingWork.prepare(handler: work)

        do {
            let request = BGContinuedProcessingTaskRequest(
                identifier: Self.taskIdentifier,
                title: String(localized: "continuousTask.scan.title"),
                subtitle: String(localized: "continuousTask.scan.subtitle")
            )
            try BGTaskScheduler.shared.submit(request)
        } catch {
            pendingWork.clear()
            work(nil)
        }
    }

    // MARK: - Full pipeline execution

    private func runFullPipeline(
        dateRange: DateRange,
        resumeSessionId: UUID?,
        deps: Dependencies,
        bgTask: BGContinuedProcessingTask?
    ) {
        bgTask?.progress.totalUnitCount = 100

        workTask?.cancel()
        workTask = Task { [weak self] in
            guard let self else { return }

            bgTask?.expirationHandler = { [weak self] in
                self?.workTask?.cancel()
            }

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
                            bgTask?.progress.completedUnitCount = Int64(Double(processed) / Double(total) * 50)
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
                bgTask?.setTaskCompleted(success: false)
                return
            }

            let scanStatus = await scanState.status
            switch scanStatus {
            case .failed(let error):
                await MainActor.run { self.phase = .failed(error) }
                bgTask?.setTaskCompleted(success: false)
                return
            case .cancelled:
                await MainActor.run { self.phase = .cancelled }
                bgTask?.setTaskCompleted(success: false)
                return
            default:
                break
            }

            bgTask?.progress.completedUnitCount = 50

            await MainActor.run { self.phase = .grouping(progress: 0) }

            let sessionDTO = try? await deps.scanStore.latestCompletedSession()
            let groups = await self.performGrouping(
                deps: deps,
                sessionId: sessionDTO?.id,
                bgTask: bgTask,
                progressBase: 50
            )

            if Task.isCancelled {
                try? await deps.scanStore.interruptActiveSessions()
                await MainActor.run { self.phase = .cancelled }
                bgTask?.setTaskCompleted(success: false)
                return
            }

            bgTask?.progress.completedUnitCount = 100
            await MainActor.run { self.phase = .completed(groups: groups) }
            bgTask?.setTaskCompleted(success: true)
        }
    }

    // MARK: - Standalone grouping execution

    private func runGrouping(
        deps: Dependencies,
        sessionId: UUID?,
        bgTask: BGContinuedProcessingTask?
    ) {
        bgTask?.progress.totalUnitCount = 100

        workTask?.cancel()
        workTask = Task { [weak self] in
            guard let self else { return }

            bgTask?.expirationHandler = { [weak self] in
                self?.workTask?.cancel()
            }

            let resolvedSessionId: UUID?
            if let sid = sessionId {
                resolvedSessionId = sid
            } else {
                resolvedSessionId = try? await deps.scanStore.latestCompletedSession()?.id
            }

            let groups = await self.performGrouping(
                deps: deps,
                sessionId: resolvedSessionId,
                bgTask: bgTask,
                progressBase: 0
            )

            if Task.isCancelled {
                try? await deps.scanStore.interruptActiveSessions()
                await MainActor.run { self.phase = .cancelled }
                bgTask?.setTaskCompleted(success: false)
                return
            }

            bgTask?.progress.completedUnitCount = 100
            await MainActor.run { self.phase = .completed(groups: groups) }
            bgTask?.setTaskCompleted(success: true)
        }
    }

    // MARK: - Shared grouping logic

    private func performGrouping(
        deps: Dependencies,
        sessionId: UUID?,
        bgTask: BGContinuedProcessingTask?,
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
                    bgTask?.progress.completedUnitCount = progressBase + Int64(p * Double(remaining))
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

@MainActor
final class PendingContinuousWork {
    static let shared = PendingContinuousWork()

    private var handler: (@MainActor (BGContinuedProcessingTask?) -> Void)?

    func prepare(handler: @escaping @MainActor (BGContinuedProcessingTask?) -> Void) {
        self.handler = handler
    }

    func start(_ task: BGContinuedProcessingTask) {
        if let handler {
            handler(task)
            self.handler = nil
        } else {
            task.setTaskCompleted(success: false)
        }
    }

    func clear() {
        handler = nil
    }
}
