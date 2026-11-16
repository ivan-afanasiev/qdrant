import BackgroundTasks
import Foundation
import UIKit
import os

@Observable
@MainActor
final class ContinuousScanCoordinator {
    nonisolated static let continuedTaskIdentifier = "com.qdrant.edge.QdrantPhotoSweep.continuousScan"

    enum Phase: Equatable {
        case idle
        case failed(AppError)
        case scanning(processed: Int, total: Int, groupsFound: Int)
        case completed(groupsFound: Int)
        case interrupted(processed: Int, total: Int)
    }

    private(set) var phase: Phase = .idle
    private(set) var groupsFoundCount = 0

    @ObservationIgnored private var workTask: Task<ScanOutcome?, Never>?
    @ObservationIgnored private var currentRunId: UUID?
    @ObservationIgnored private var cancelledRuns: Set<UUID> = []
    @ObservationIgnored private var isStopping = false
    @ObservationIgnored private var backgroundTaskManager = BackgroundTaskManager()
    @ObservationIgnored private var lastDateRange: DateRange?
    @ObservationIgnored private var lastResumeSessionId: UUID?
    @ObservationIgnored private var lastDeps: (any DependencyProviding)?
    @ObservationIgnored private var allowsContinuedSupport = false
    @ObservationIgnored private var pendingIdentifier: String?

    private static weak var foregroundCoordinator: ContinuousScanCoordinator?
    private static var requests: [String: (ContinuousScanCoordinator, UUID)] = [:]
    static var hasActiveScan: Bool { foregroundCoordinator?.isActive == true }

    var scanProgress: Double {
        switch phase {
        case .scanning(let processed, let total, _) where total > 0,
             .interrupted(let processed, let total) where total > 0:
            Double(processed) / Double(total)
        case .completed: 1
        default: 0
        }
    }

    var isActive: Bool {
        if case .scanning = phase { return true }
        return false
    }

    var isInterrupted: Bool {
        if case .interrupted = phase { return true }
        return false
    }

    private static var continuedRegistrationSucceeded = false

    static func register() {
        guard #available(iOS 26.0, *) else { return }
        continuedRegistrationSucceeded = BGTaskScheduler.shared.register(
            forTaskWithIdentifier: continuedTaskIdentifier + ".*", using: nil
        ) { task in
            guard let task = task as? BGContinuedProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor in
                guard let (coordinator, runId) = requests.removeValue(forKey: task.identifier),
                      coordinator.currentRunId == runId else {
                    task.setTaskCompleted(success: false)
                    return
                }
                coordinator.backgroundTaskManager.attachContinuedTask(task) { [weak coordinator] in
                    // A system-UI cancellation must not automatically restart on foreground entry.
                    Task { @MainActor in
                        guard coordinator?.currentRunId == runId else { return }
                        await coordinator?.cancel()
                    }
                }
                coordinator.runPipeline(runId: runId)
            }
        }
        if !continuedRegistrationSucceeded {
            AppLog.scan.error("Continued processing registration rejected; using ordinary scan execution. Permitted identifiers: \(String(describing: Bundle.main.object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers")))")
        }
    }

    func startPipeline(
        dateRange: DateRange,
        resumeSessionId: UUID?,
        deps: any DependencyProviding,
        requestContinuedSupport: Bool = false
    ) {
        guard !isActive, !isStopping, workTask == nil else { return }
        lastDateRange = dateRange
        lastResumeSessionId = resumeSessionId
        lastDeps = deps
        allowsContinuedSupport = requestContinuedSupport
        let runId = UUID()
        currentRunId = runId
        Self.foregroundCoordinator = self
        groupsFoundCount = 0
        phase = .scanning(processed: 0, total: 0, groupsFound: 0)

        // Continued processing is for user-initiated jobs; automatic scans use the fallback.
        if requestContinuedSupport, Self.continuedRegistrationSucceeded, UIApplication.shared.applicationState == .active {
            let identifier = Self.continuedTaskIdentifier + "." + runId.uuidString
            pendingIdentifier = identifier
            Self.requests[identifier] = (self, runId)
            if backgroundTaskManager.requestContinuedTaskSupport(identifier: identifier) { return }
            Self.requests.removeValue(forKey: identifier)
            pendingIdentifier = nil
        }
        runPipeline(runId: runId)
    }

    func cancel() async {
        guard !isStopping else {
            _ = await workTask?.value
            return
        }
        isStopping = true
        let runId = currentRunId
        if let runId { cancelledRuns.insert(runId) }
        currentRunId = nil
        removePendingRequest()
        let task = workTask
        task?.cancel()
        let outcome = await task?.value
        // Also handles cancellation while waiting for the system launch handler.
        if let sessionId = outcome?.sessionId ?? lastResumeSessionId, let deps = lastDeps {
            do {
                try await deps.scanStore.updateSessionStatus(sessionId, status: .cancelled, indexedPhotos: nil)
            } catch {
                AppLog.scan.error("Unable to persist user cancellation: \(error)")
            }
        }
        backgroundTaskManager.finish(success: false)
        workTask = nil
        if let runId { cancelledRuns.remove(runId) }
        lastDateRange = nil
        lastResumeSessionId = nil
        lastDeps = nil
        phase = .idle
        isStopping = false
    }

    func resumeIfInterrupted() {
        guard isInterrupted, !isStopping, let range = lastDateRange, let deps = lastDeps else { return }
        startPipeline(
            dateRange: range, resumeSessionId: lastResumeSessionId,
            deps: deps, requestContinuedSupport: allowsContinuedSupport
        )
    }

    func retryFailedScan() {
        guard case .failed = phase, !isStopping,
              let range = lastDateRange, let deps = lastDeps else { return }
        startPipeline(dateRange: range, resumeSessionId: lastResumeSessionId,
                      deps: deps, requestContinuedSupport: allowsContinuedSupport)
    }

    func beginExtendedBackgroundExecution() {
        guard let runId = currentRunId else { return }
        backgroundTaskManager.beginExtendedBackgroundExecution { [weak self] in
            Task { @MainActor in
                guard self?.currentRunId == runId else { return }
                self?.workTask?.cancel()
            }
        }
    }

    func endExtendedBackgroundExecution() {
        backgroundTaskManager.endUIBackgroundTask()
    }

    private func runPipeline(runId: UUID) {
        guard currentRunId == runId, workTask == nil,
              let range = lastDateRange, let deps = lastDeps else { return }
        let resumeId = lastResumeSessionId
        workTask = Task {
            let outcome = await ScanExecutionController.shared.run(replacingCurrent: true) {
                let state = ScanState()
                let observation = Task { @MainActor in
                    while !Task.isCancelled {
                        do { try await Task.sleep(for: .milliseconds(150)) } catch { break }
                        guard self.currentRunId == runId else { break }
                        if case .scanning(let processed, let total) = state.status {
                            self.phase = .scanning(processed: processed, total: total, groupsFound: self.groupsFoundCount)
                            self.backgroundTaskManager.updateContinuedTaskProgress(processed, total)
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
                    onGroupCountChanged: { count in
                        Task { @MainActor in
                            guard self.currentRunId == runId else { return }
                            self.groupsFoundCount = count
                        }
                    },
                    onSessionStarted: { sessionId in
                        await MainActor.run {
                            guard self.currentRunId == runId else { return }
                            self.lastResumeSessionId = sessionId
                        }
                    }
                )
                let result = await pipeline.run(dateRange: range, state: state, resumeSessionId: resumeId)
                observation.cancel()
                // Persist cancellation before releasing the scan lease to another worker.
                if self.cancelledRuns.contains(runId), let sessionId = result.sessionId {
                    do {
                        try await deps.scanStore.updateSessionStatus(sessionId, status: .cancelled, indexedPhotos: nil)
                    } catch {
                        AppLog.scan.error("Unable to persist cancellation: \(error)")
                    }
                }
                return result
            }
            guard self.currentRunId == runId else { return outcome }
            self.workTask = nil
            self.currentRunId = nil
            self.removePendingRequest()
            self.backgroundTaskManager.finish(success: outcome?.succeeded == true)
            self.lastResumeSessionId = outcome?.sessionId ?? self.lastResumeSessionId
            if let outcome, outcome.succeeded {
                self.groupsFoundCount = outcome.groupsFound
                self.phase = .completed(groupsFound: outcome.groupsFound)
            } else if let outcome, case .failed(let error) = outcome.status {
                self.phase = .failed(error)
            } else {
                let progress: (Int, Int)
                if case .scanning(let processed, let total, _) = self.phase {
                    progress = (processed, total)
                } else {
                    progress = (0, 0)
                }
                self.phase = .interrupted(processed: progress.0, total: progress.1)
                // Activation can precede cancellation cleanup; do not miss that resume opportunity.
                if Task.isCancelled, UIApplication.shared.applicationState == .active {
                    self.resumeIfInterrupted()
                }
            }
            return outcome
        }
    }

    private func removePendingRequest() {
        if let pendingIdentifier {
            Self.requests.removeValue(forKey: pendingIdentifier)
            self.pendingIdentifier = nil
        }
    }
}
