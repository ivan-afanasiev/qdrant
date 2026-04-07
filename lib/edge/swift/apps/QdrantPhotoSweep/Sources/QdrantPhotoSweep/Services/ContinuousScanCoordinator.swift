import BackgroundTasks
import Foundation
import UIKit

@Observable
@MainActor
final class ContinuousScanCoordinator {
    static let continuedTaskIdentifier = "com.qdrant.edge.PhotoSweep.continuousScan"

    enum Phase: Equatable {
        case idle
        case scanning(processed: Int, total: Int, groupsFound: Int)
        case completed(groupsFound: Int)
        case failed(AppError)
        case cancelled
    }

    enum Action {
        case didStartPipeline
        case didUpdateProgress(processed: Int, total: Int)
        case didFindGroups(count: Int)
        case didCompleteScan(groupsFound: Int)
        case didFail(AppError)
        case didCancel
    }

    private(set) var phase: Phase = .idle
    private(set) var groupsFoundCount: Int = 0
    private var workTask: Task<Void, Never>?
    private var backgroundTaskManager = BackgroundTaskManager()

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

    // MARK: - Reducer

    func reduce(_ action: Action) {
        switch action {
        case .didStartPipeline:
            phase = .scanning(processed: 0, total: 0, groupsFound: 0)
            groupsFoundCount = 0

        case .didUpdateProgress(let processed, let total):
            if case .scanning(_, _, let groups) = phase {
                phase = .scanning(processed: processed, total: total, groupsFound: groups)
            }

        case .didFindGroups(let count):
            groupsFoundCount = count
            if case .scanning(let p, let t, _) = phase {
                phase = .scanning(processed: p, total: t, groupsFound: count)
            }

        case .didCompleteScan(let groupsFound):
            phase = .completed(groupsFound: groupsFound)

        case .didFail(let error):
            phase = .failed(error)

        case .didCancel:
            phase = .cancelled
        }
    }

    // MARK: - Registration (called from App.init on iOS 26+)

    nonisolated static func register() {
        guard #available(iOS 26.0, *) else { return }
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: continuedTaskIdentifier,
            using: nil
        ) { task in
            guard let continuedTask = task as? BGContinuedProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor in
                ContinuousScanCoordinator.handleContinuedTask(continuedTask)
            }
        }
    }

    @available(iOS 26.0, *)
    private static var activeCoordinator: ContinuousScanCoordinator?

    @available(iOS 26.0, *)
    @MainActor
    private static func handleContinuedTask(_ task: BGContinuedProcessingTask) {
        guard let coordinator = activeCoordinator else {
            task.setTaskCompleted(success: false)
            return
        }
        coordinator.backgroundTaskManager.attachContinuedTask(task, cancelWork: { [weak coordinator] in
            Task { @MainActor in
                coordinator?.workTask?.cancel()
            }
        })
    }

    // MARK: - Start Pipeline

    func startPipeline(
        dateRange: DateRange,
        resumeSessionId: UUID?,
        deps: Dependencies
    ) {
        guard !isActive else { return }
        reduce(.didStartPipeline)

        runPipeline(dateRange: dateRange, resumeSessionId: resumeSessionId, deps: deps)
        backgroundTaskManager.requestContinuedTaskSupport(
            identifier: Self.continuedTaskIdentifier,
            registerSelf: { self.setActiveCoordinator() }
        )
    }

    func cancel() {
        workTask?.cancel()
        workTask = nil
        backgroundTaskManager.completeContinuedTask(success: false)
        clearActiveCoordinator()
        backgroundTaskManager.endUIBackgroundTask()
        reduce(.didCancel)
    }

    // MARK: - Extended execution (all iOS versions)

    func beginExtendedBackgroundExecution() {
        backgroundTaskManager.beginExtendedBackgroundExecution { [weak self] in
            Task { @MainActor in
                self?.workTask?.cancel()
            }
        }
    }

    // MARK: - Pipeline builder

    private func makePipeline(deps: Dependencies) -> ScanPipeline {
        ScanPipeline(
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
            onGroupCountChanged: { [weak self] count in
                Task { @MainActor [weak self] in
                    self?.reduce(.didFindGroups(count: count))
                }
            }
        )
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
                    if case .scanning(let processed, let total) = status {
                        self.reduce(.didUpdateProgress(processed: processed, total: total))
                        self.backgroundTaskManager.updateContinuedTaskProgress(processed, total)
                    }
                }
            }

            let pipeline = self.makePipeline(deps: deps)

            await pipeline.run(
                dateRange: dateRange,
                state: scanState,
                resumeSessionId: resumeSessionId
            )

            scanObservation.cancel()

            if Task.isCancelled {
                try? await deps.scanStore.interruptActiveSessions()
                await MainActor.run { self.reduce(.didCancel) }
                self.finishBackgroundTasks(success: false)
                return
            }

            let scanStatus = await scanState.status
            switch scanStatus {
            case .failed(let error):
                await MainActor.run { self.reduce(.didFail(error)) }
                self.finishBackgroundTasks(success: false)
            case .cancelled:
                await MainActor.run { self.reduce(.didCancel) }
                self.finishBackgroundTasks(success: false)
            default:
                let count = await MainActor.run { self.groupsFoundCount }
                await MainActor.run { self.reduce(.didCompleteScan(groupsFound: count)) }
                self.finishBackgroundTasks(success: true)
            }
        }
    }

    private func finishBackgroundTasks(success: Bool) {
        backgroundTaskManager.completeContinuedTask(success: success)
        clearActiveCoordinator()
        backgroundTaskManager.endUIBackgroundTask()
    }

    // MARK: - Active Coordinator Management

    private func setActiveCoordinator() {
        guard #available(iOS 26.0, *) else { return }
        Self.activeCoordinator = self
    }

    private func clearActiveCoordinator() {
        guard #available(iOS 26.0, *) else { return }
        Self.activeCoordinator = nil
    }
}
