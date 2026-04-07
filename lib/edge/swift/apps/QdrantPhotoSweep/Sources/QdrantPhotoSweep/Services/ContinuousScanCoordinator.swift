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

    private(set) var phase: Phase = .idle
    private(set) var groupsFoundCount: Int = 0
    private var workTask: Task<Void, Never>?
    private var uiBackgroundTaskId: UIBackgroundTaskIdentifier = .invalid
    private var continuedTaskHandle: AnyObject?

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
        coordinator.attachContinuedTask(task)
    }

    @available(iOS 26.0, *)
    private func attachContinuedTask(_ task: BGContinuedProcessingTask) {
        continuedTaskHandle = task
        task.progress.totalUnitCount = 100
        task.expirationHandler = { [weak self] in
            self?.workTask?.cancel()
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
        groupsFoundCount = 0

        runPipeline(dateRange: dateRange, resumeSessionId: resumeSessionId, deps: deps)
        requestContinuedTaskSupport()
    }

    func cancel() {
        workTask?.cancel()
        workTask = nil
        completeContinuedTask(success: false)
        clearActiveCoordinator()
        endUIBackgroundTask()
        phase = .cancelled
    }

    // MARK: - Extended execution (all iOS versions)

    func beginExtendedBackgroundExecution() {
        guard uiBackgroundTaskId == .invalid else { return }
        uiBackgroundTaskId = UIApplication.shared.beginBackgroundTask(
            withName: "PhotoSweep.scan"
        ) { [weak self] in
            self?.workTask?.cancel()
            self?.endUIBackgroundTask()
        }
    }

    private func endUIBackgroundTask() {
        guard uiBackgroundTaskId != .invalid else { return }
        UIApplication.shared.endBackgroundTask(uiBackgroundTaskId)
        uiBackgroundTaskId = .invalid
    }

    // MARK: - iOS 26+ Continued Task (optional enhancement)

    private func requestContinuedTaskSupport() {
        guard #available(iOS 26.0, *) else { return }
        Self.activeCoordinator = self
        do {
            let request = BGContinuedProcessingTaskRequest(
                identifier: Self.continuedTaskIdentifier,
                title: String(localized: "continuousTask.scan.title"),
                subtitle: String(localized: "continuousTask.scan.subtitle")
            )
            try BGTaskScheduler.shared.submit(request)
        } catch {
            Self.activeCoordinator = nil
        }
    }

    private func updateContinuedTaskProgress(_ processed: Int, _ total: Int) {
        guard #available(iOS 26.0, *),
              let task = continuedTaskHandle as? BGContinuedProcessingTask else { return }
        if total > 0 {
            let pct = Int64(Double(processed) / Double(total) * 100)
            task.progress.completedUnitCount = pct
        }
    }

    private func completeContinuedTask(success: Bool) {
        guard #available(iOS 26.0, *),
              let task = continuedTaskHandle as? BGContinuedProcessingTask else { return }
        task.setTaskCompleted(success: success)
        continuedTaskHandle = nil
    }

    private func clearActiveCoordinator() {
        guard #available(iOS 26.0, *) else { return }
        Self.activeCoordinator = nil
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
                    guard let self else { return }
                    self.groupsFoundCount = count
                    if case .scanning(let p, let t, _) = self.phase {
                        self.phase = .scanning(processed: p, total: t, groupsFound: count)
                    }
                }
            }
        )
    }

    // MARK: - Pipeline execution (always runs immediately)

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
                        let groupCount = self.groupsFoundCount
                        self.phase = .scanning(processed: processed, total: total, groupsFound: groupCount)
                        self.updateContinuedTaskProgress(processed, total)
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
                await MainActor.run { self.phase = .cancelled }
                self.completeContinuedTask(success: false)
                self.clearActiveCoordinator()
                self.endUIBackgroundTask()
                return
            }

            let scanStatus = await scanState.status
            switch scanStatus {
            case .failed(let error):
                await MainActor.run { self.phase = .failed(error) }
                self.completeContinuedTask(success: false)
                self.clearActiveCoordinator()
                self.endUIBackgroundTask()
            case .cancelled:
                await MainActor.run { self.phase = .cancelled }
                self.completeContinuedTask(success: false)
                self.clearActiveCoordinator()
                self.endUIBackgroundTask()
            default:
                let count = await MainActor.run { self.groupsFoundCount }
                await MainActor.run { self.phase = .completed(groupsFound: count) }
                self.completeContinuedTask(success: true)
                self.clearActiveCoordinator()
                self.endUIBackgroundTask()
            }
        }
    }
}
