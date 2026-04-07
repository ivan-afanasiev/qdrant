import BackgroundTasks
import Foundation
import SwiftData
import UserNotifications

enum BackgroundScanService {
    static let taskIdentifier = "com.qdrant.edge.PhotoSweep.backgroundScan"

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
        try? BGTaskScheduler.shared.submit(request)
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

        defer { Task { await deps.vectorStore.close() } }

        let bgScanState = await ScanState()
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
            onGroupCountChanged: { count in
                groupCount = count
            }
        )

        // Priority 1: Resume an interrupted session
        if let interrupted = try? await deps.scanStore.latestInterruptedSession() {
            let range = DateRange(start: interrupted.rangeStart, end: interrupted.rangeEnd)
            await pipeline.run(dateRange: range, state: bgScanState, resumeSessionId: interrupted.id)

            if Task.isCancelled {
                try? await deps.scanStore.interruptActiveSessions()
                return -1
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
                await pipeline.run(dateRange: incrementalRange, state: bgScanState)

                if Task.isCancelled {
                    try? await deps.scanStore.interruptActiveSessions()
                    return -1
                }
            }
        }

        guard !Task.isCancelled else { return -1 }

        if groupCount > 0 {
            await postLocalNotification(groupCount: groupCount)
        }

        return groupCount
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
