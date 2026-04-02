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

    static func schedule() {
        let request = BGProcessingTaskRequest(identifier: taskIdentifier)
        request.requiresExternalPower = false
        request.requiresNetworkConnectivity = false
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    /// Mark any in-progress sessions as interrupted and flush pending work.
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
        let scanStore = SwiftDataScanStore(modelContainer: modelContainer)
        let photoLibrary = PhotoLibraryService()
        let embeddingService = VisionEmbeddingService()

        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let shardDir = documentsPath.appendingPathComponent("qdrant-edge")
        let vectorStore = QdrantVectorStore(path: shardDir.path, dimensions: 0)
        await vectorStore.restoreDimensionsFromDisk()

        defer { Task { await vectorStore.close() } }

        let bgScanState = await ScanState()
        let pipeline = ScanPipeline(
            photoLibrary: photoLibrary,
            embeddingService: embeddingService,
            vectorStore: vectorStore,
            scanStore: scanStore,
            configureDimensions: { dims in
                await vectorStore.updateDimensions(dims)
            }
        )

        // Priority 1: Resume an interrupted session
        if let interrupted = try? await scanStore.latestInterruptedSession() {
            let range = DateRange(start: interrupted.rangeStart, end: interrupted.rangeEnd)
            await pipeline.run(dateRange: range, state: bgScanState, resumeSessionId: interrupted.id)

            if Task.isCancelled {
                try? await scanStore.interruptActiveSessions()
                return -1
            }
        }

        // Priority 1.5: Resume interrupted grouping
        if let groupingInterrupted = try? await scanStore.latestGroupingInterruptedSession() {
            try? await scanStore.updateSessionStatus(groupingInterrupted.id, status: .grouping, indexedPhotos: nil)

            let detectionState = await DuplicateDetectionState()
            await detectionState.findDuplicates(
                vectorStore: vectorStore,
                threshold: AppSettings.defaultSimilarityThreshold,
                scanStore: scanStore
            )

            if Task.isCancelled {
                try? await scanStore.updateSessionStatus(groupingInterrupted.id, status: .groupingInterrupted, indexedPhotos: nil)
                return -1
            }

            try? await scanStore.updateSessionStatus(groupingInterrupted.id, status: .completed, indexedPhotos: nil)

            if case .complete(let groups) = await detectionState.status, groups.count > 0 {
                await postLocalNotification(groupCount: groups.count)
                return groups.count
            }
        }

        // Priority 2: Incremental scan for new photos since last completed session
        if let session = try? await scanStore.latestCompletedSession() {
            let newCount = (try? await scanStore.countNewPhotosSince(
                date: session.scannedAt,
                in: DateRange(start: session.rangeStart, end: session.rangeEnd),
                using: photoLibrary
            )) ?? 0

            if newCount > 0 {
                let incrementalRange = DateRange(start: session.scannedAt, end: .now)
                await pipeline.run(dateRange: incrementalRange, state: bgScanState)

                if Task.isCancelled {
                    try? await scanStore.interruptActiveSessions()
                    return -1
                }
            }
        }

        // Run duplicate detection
        guard !Task.isCancelled else { return -1 }

        let detectionState = await DuplicateDetectionState()
        let threshold = AppSettings.defaultSimilarityThreshold
        await detectionState.findDuplicates(
            vectorStore: vectorStore,
            threshold: threshold,
            scanStore: scanStore
        )

        guard !Task.isCancelled else { return -1 }

        var groupCount = 0
        if case .complete(let groups) = await detectionState.status {
            groupCount = groups.count
        }

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
