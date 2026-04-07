import BackgroundTasks
import Foundation

@Observable
@MainActor
final class ContinuousScanCoordinator {
    static let taskIdentifier = "com.qdrant.edge.PhotoSweep.continuousScan"

    enum Phase: Equatable {
        case idle
        case scanning(processed: Int, total: Int, groupsFound: Int)
        case completed(groups: [DuplicateGroup])
        case failed(AppError)
        case cancelled
    }

    private(set) var phase: Phase = .idle
    private(set) var discoveredGroups: [DuplicateGroup] = []
    private var workTask: Task<Void, Never>?
    private var bgTaskHandle: AnyObject?

    var scanProgress: Double {
        switch phase {
        case .scanning(let processed, let total, _) where total > 0:
            Double(processed) / Double(total)
        case .completed:
            1.0
        default:
            0
        }
    }

    var isActive: Bool {
        if case .scanning = phase { return true }
        return false
    }

    var groupsFoundCount: Int {
        switch phase {
        case .scanning(_, _, let count): count
        case .completed(let groups): groups.count
        default: discoveredGroups.count
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

    // MARK: - Start Pipeline

    func startPipeline(
        dateRange: DateRange,
        resumeSessionId: UUID?,
        deps: Dependencies
    ) {
        guard !isActive else { return }
        phase = .scanning(processed: 0, total: 0, groupsFound: 0)
        discoveredGroups = []

        requestBackgroundSupport()
        runPipeline(dateRange: dateRange, resumeSessionId: resumeSessionId, deps: deps)
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

    private func completeBgTask(success: Bool) {
        guard #available(iOS 26.0, *),
              let task = bgTaskHandle as? BGContinuedProcessingTask else { return }
        task.setTaskCompleted(success: success)
        bgTaskHandle = nil
    }

    // MARK: - Pipeline execution

    private func runPipeline(
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
                        let groupCount = self.discoveredGroups.count
                        self.phase = .scanning(processed: processed, total: total, groupsFound: groupCount)
                        if total > 0 {
                            self.updateBgProgress(Int64(Double(processed) / Double(total) * 100))
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
                },
                similarityThreshold: deps.settings.similarityThreshold,
                onGroupsUpdated: { [weak self] groups in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        self.discoveredGroups = groups
                        if case .scanning(let p, let t, _) = self.phase {
                            self.phase = .scanning(processed: p, total: t, groupsFound: groups.count)
                        }
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

            self.updateBgProgress(100)
            let finalGroups = await MainActor.run { self.discoveredGroups }
            await MainActor.run { self.phase = .completed(groups: finalGroups) }
            self.completeBgTask(success: true)
            self.clearActiveCoordinator()
        }
    }
}
