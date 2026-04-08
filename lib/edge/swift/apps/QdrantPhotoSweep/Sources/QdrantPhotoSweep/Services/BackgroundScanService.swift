import BackgroundTasks
import Foundation
import SwiftData
import UserNotifications

enum BackgroundScanService {
    static let taskIdentifier = "com.qdrant.edge.PhotoSweep.backgroundScan"
    private static let workerID = "background-\(UUID().uuidString.lowercased())"

    static func register(modelContainer: ModelContainer) {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: taskIdentifier,
            using: nil
        ) { task in
            guard let bgTask = task as? BGProcessingTask else { return }
            handleBackgroundTask(bgTask, modelContainer: modelContainer)
        }
    }

    static func schedule(urgent: Bool = false) {
        let request = BGProcessingTaskRequest(identifier: taskIdentifier)
        request.requiresExternalPower = false
        request.requiresNetworkConnectivity = false
        request.earliestBeginDate = urgent ? Date() : Date(timeIntervalSinceNow: 15 * 60)
        if urgent {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskIdentifier)
        }
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            AppLog.background.error("Failed to schedule background scan (urgent: \(urgent)): \(error.localizedDescription)")
        }
    }

    static func interruptActiveSessions(scanStore: any ScanSessionStoring) {
        Task { try? await scanStore.interruptActiveSessions() }
    }

    private static func handleBackgroundTask(_ task: BGProcessingTask, modelContainer: ModelContainer) {
        let workTask = Task {
            await performBackgroundWork(modelContainer: modelContainer)
        }

        task.expirationHandler = {
            workTask.cancel()
        }

        Task {
            let groupCount = await workTask.value
            task.setTaskCompleted(success: groupCount >= 0)
            schedule()
        }
    }

    @discardableResult
    private static func performBackgroundWork(modelContainer: ModelContainer) async -> Int {
        if await ContinuousScanCoordinator.isForegroundScanActive {
            return 0
        }

        let deps = await AppDependencies.forBackground(modelContainer: modelContainer)
        try? await deps.scanStore.recoverPendingOperations()

        defer { Task { await deps.vectorStore.close() } }

        var groupCount = 0

        let pipeline = ScanPipeline(
            photoLibrary: deps.photoLibrary,
            embeddingService: deps.embeddingService,
            vectorStore: deps.vectorStore,
            scanStore: deps.scanStore,
            configureDimensions: { dims in
                if let qdrantStore = deps.vectorStore as? QdrantVectorStore {
                    await qdrantStore.updateDimensions(dims)
                }
            },
            ownerID: workerID,
            onGroupCountChanged: { count in
                groupCount = count
            }
        )

        // Priority 1: Resume an interrupted session
        if let interrupted = try? await deps.scanStore.latestInterruptedSession() {
            let range = DateRange(start: interrupted.rangeStart, end: interrupted.rangeEnd)
            let result = await runPipeline(
                pipeline,
                dateRange: range,
                resumeSessionId: interrupted.id
            )
            switch result {
            case .cancelled:
                try? await deps.scanStore.interruptActiveSessions()
                return -1
            case .failed:
                return -1
            case .completed:
                if groupCount > 0 {
                    await postLocalNotification(groupCount: groupCount)
                }
                return groupCount
            }
        }

        // Priority 2: Incremental scan for new photos since last completed session
        if let session = try? await deps.scanStore.latestCompletedSession() {
            let newCount = (try? await deps.scanStore.countNewPhotosSince(
                date: session.scannedAt,
                in: DateRange(start: session.rangeStart, end: session.rangeEnd),
                using: deps.photoLibrary
            )) ?? 0

            if newCount > 0 {
                let incrementalRange = DateRange(start: session.scannedAt, end: .now)
                let result = await runPipeline(
                    pipeline,
                    dateRange: incrementalRange,
                    resumeSessionId: nil
                )
                switch result {
                case .cancelled:
                    try? await deps.scanStore.interruptActiveSessions()
                    return -1
                case .failed:
                    return -1
                case .completed:
                    break
                }
            }
        }

        guard !Task.isCancelled else { return -1 }

        if groupCount > 0 {
            await postLocalNotification(groupCount: groupCount)
        }

        return groupCount
    }

    private enum PipelineRunResult {
        case completed
        case failed
        case cancelled
    }

    private static func runPipeline(
        _ pipeline: ScanPipeline,
        dateRange: DateRange,
        resumeSessionId: UUID?
    ) async -> PipelineRunResult {
        let state = await ScanState()
        await pipeline.run(dateRange: dateRange, state: state, resumeSessionId: resumeSessionId)

        if Task.isCancelled {
            return .cancelled
        }

        let status = await state.status
        switch status {
        case .failed:
            return .failed
        case .cancelled:
            return .cancelled
        case .completed, .idle, .scanning:
            return .completed
        }
    }

    private static func postLocalNotification(groupCount: Int) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            _ = try? await center.requestAuthorization(options: [.alert, .badge, .sound])
            return
        }

        let content = UNMutableNotificationContent()
        content.title = L10n.backgroundScanCompleteTitle
        content.body = L10n.backgroundScanCompleteBody(groupCount)
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "backgroundScan-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        try? await center.add(request)
    }
}
