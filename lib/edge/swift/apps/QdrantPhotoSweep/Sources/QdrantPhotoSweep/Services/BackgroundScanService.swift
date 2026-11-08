import BackgroundTasks
import Foundation
import Photos
import SwiftData
import UserNotifications

enum BackgroundScanService {
    static let taskIdentifier = "com.qdrant.edge.PhotoSweep.backgroundScan"

    static func register(modelContainer: ModelContainer) {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            guard let task = task as? BGProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            let work = Task { await performBackgroundWork(modelContainer: modelContainer) }
            task.expirationHandler = { work.cancel() }
            Task {
                let success = await work.value
                task.setTaskCompleted(success: success)
                schedule()
            }
        }
    }

    static func schedule(urgent: Bool = false) {
        let request = BGProcessingTaskRequest(identifier: taskIdentifier)
        request.requiresExternalPower = false
        request.requiresNetworkConnectivity = false
        request.earliestBeginDate = urgent ? Date() : Date(timeIntervalSinceNow: 15 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            AppLog.scan.error("Background scan scheduling failed: \(error)")
        }
    }

    static func incrementalRange(since session: ScanSessionDTO, now: Date = .now) -> DateRange? {
        guard session.scannedAt < now else { return nil }
        return DateRange(start: session.scannedAt, end: now)
    }

    @MainActor
    private static func performBackgroundWork(modelContainer: ModelContainer) async -> Bool {
        guard !Task.isCancelled else { return false }
        guard !ContinuousScanCoordinator.hasActiveScan else { return true }
        let authorization = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard authorization == .authorized || authorization == .limited else { return false }
        do {
            let deps = try await AppDependencies.shared(modelContainer: modelContainer)
            guard deps.settings.hasCompletedOnboarding else { return false }
            let result = await ScanExecutionController.shared.run(replacingCurrent: false) {
                do {
                    try Task.checkCancellation()
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
                        similarityThreshold: deps.settings.similarityThreshold
                    )
                    var groupsFound = 0
                    if let interrupted = try await deps.scanStore.latestInterruptedSession() {
                        let outcome = await pipeline.run(
                            dateRange: DateRange(start: interrupted.rangeStart, end: interrupted.rangeEnd),
                            state: ScanState(), resumeSessionId: interrupted.id
                        )
                        guard outcome.succeeded else { return outcome }
                        groupsFound += outcome.groupsFound
                    }
                    try Task.checkCancellation()
                    if let session = try await deps.scanStore.latestCompletedSession(),
                       let range = incrementalRange(since: session),
                       try await deps.photoLibrary.countAssets(in: range) > 0 {
                        let outcome = await pipeline.run(dateRange: range, state: ScanState())
                        guard outcome.succeeded else { return outcome }
                        groupsFound += outcome.groupsFound
                    }
                    try Task.checkCancellation()
                    return ScanOutcome(sessionId: nil, status: .completed, groupsFound: groupsFound)
                } catch {
                    if Task.isCancelled {
                        return ScanOutcome(sessionId: nil, status: .interrupted, groupsFound: 0)
                    }
                    return ScanOutcome(
                        sessionId: nil,
                        status: .failed(error as? AppError ?? .unknown(error.localizedDescription)),
                        groupsFound: 0
                    )
                }
            }
            guard !Task.isCancelled else { return false }
            // Another worker owns scanning; this request has nothing to do.
            guard let result else { return true }
            if result.succeeded, result.groupsFound > 0 {
                await postLocalNotification(groupCount: result.groupsFound)
            }
            return result.succeeded
        } catch {
            AppLog.scan.error("Background scan failed: \(error)")
            return false
        }
    }

    private static func postLocalNotification(groupCount: Int) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
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
