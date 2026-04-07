import BackgroundTasks
import Foundation
import UIKit

@MainActor
final class BackgroundTaskManager {
    private var uiBackgroundTaskId: UIBackgroundTaskIdentifier = .invalid
    private var continuedTaskHandle: AnyObject?

    // MARK: - UIApplication Background Task (all iOS versions)

    func beginExtendedBackgroundExecution(onExpiration: @escaping @Sendable () -> Void) {
        guard uiBackgroundTaskId == .invalid else { return }
        uiBackgroundTaskId = UIApplication.shared.beginBackgroundTask(
            withName: "PhotoSweep.scan"
        ) { [weak self] in
            onExpiration()
            self?.endUIBackgroundTask()
        }
    }

    func endUIBackgroundTask() {
        guard uiBackgroundTaskId != .invalid else { return }
        UIApplication.shared.endBackgroundTask(uiBackgroundTaskId)
        uiBackgroundTaskId = .invalid
    }

    // MARK: - iOS 26+ BGContinuedProcessingTask

    func requestContinuedTaskSupport(
        identifier: String,
        registerSelf: () -> Void
    ) {
        guard #available(iOS 26.0, *) else { return }
        registerSelf()
        do {
            let request = BGContinuedProcessingTaskRequest(
                identifier: identifier,
                title: String(localized: "continuousTask.scan.title"),
                subtitle: String(localized: "continuousTask.scan.subtitle")
            )
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Fallback: work continues without Live Activity
        }
    }

    func attachContinuedTask(_ task: AnyObject, cancelWork: @escaping @Sendable () -> Void) {
        guard #available(iOS 26.0, *),
              let bgTask = task as? BGContinuedProcessingTask else { return }
        continuedTaskHandle = bgTask
        bgTask.progress.totalUnitCount = 100
        bgTask.expirationHandler = cancelWork
    }

    func updateContinuedTaskProgress(_ processed: Int, _ total: Int) {
        guard #available(iOS 26.0, *),
              let task = continuedTaskHandle as? BGContinuedProcessingTask else { return }
        if total > 0 {
            let pct = Int64(Double(processed) / Double(total) * 100)
            task.progress.completedUnitCount = pct
        }
    }

    func completeContinuedTask(success: Bool) {
        guard #available(iOS 26.0, *),
              let task = continuedTaskHandle as? BGContinuedProcessingTask else { return }
        task.setTaskCompleted(success: success)
        continuedTaskHandle = nil
    }
}
