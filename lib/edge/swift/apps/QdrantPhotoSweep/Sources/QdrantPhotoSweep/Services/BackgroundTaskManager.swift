import BackgroundTasks
import Foundation
import UIKit
import os

@MainActor
final class BackgroundTaskManager {
    private var uiBackgroundTaskId: UIBackgroundTaskIdentifier = .invalid
    private var continuedTaskHandle: AnyObject?
    private var requestIdentifier: String?
    private var uiTaskGeneration: UUID?

    var hasContinuedTask: Bool { continuedTaskHandle != nil }

    func beginExtendedBackgroundExecution(onExpiration: @escaping @Sendable () -> Void) {
        guard !hasContinuedTask, uiBackgroundTaskId == .invalid else { return }
        let generation = UUID()
        uiTaskGeneration = generation
        uiBackgroundTaskId = UIApplication.shared.beginBackgroundTask(withName: "PhotoSweep.scan") { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.uiTaskGeneration == generation, !self.hasContinuedTask else { return }
                onExpiration()
                self.endUIBackgroundTask()
            }
        }
    }

    func endUIBackgroundTask() {
        guard uiBackgroundTaskId != .invalid else { return }
        UIApplication.shared.endBackgroundTask(uiBackgroundTaskId)
        uiBackgroundTaskId = .invalid
        uiTaskGeneration = nil
    }

    /// No queued job: if admission fails, the caller explicitly chooses ordinary foreground execution.
    func requestContinuedTaskSupport(identifier: String) -> Bool {
        guard #available(iOS 26.0, *) else { return false }
        let request = BGContinuedProcessingTaskRequest(
            identifier: identifier,
            title: String(localized: "continuousTask.scan.title"),
            subtitle: String(localized: "continuousTask.scan.subtitle")
        )
        request.strategy = .fail
        requestIdentifier = identifier
        do {
            try BGTaskScheduler.shared.submit(request)
            return true
        } catch {
            requestIdentifier = nil
            AppLog.scan.error("Continued-processing request failed: \(error)")
            return false
        }
    }

    @available(iOS 26.0, *)
    func attachContinuedTask(_ task: BGContinuedProcessingTask, cancelWork: @escaping @Sendable () -> Void) {
        continuedTaskHandle = task
        task.progress.totalUnitCount = 100
        task.expirationHandler = cancelWork
        // The short UIKit allowance must not cancel an admitted continued task.
        endUIBackgroundTask()
    }

    func updateContinuedTaskProgress(_ processed: Int, _ total: Int) {
        guard #available(iOS 26.0, *),
              let task = continuedTaskHandle as? BGContinuedProcessingTask,
              total > 0 else { return }
        task.progress.completedUnitCount = min(100, Int64(Double(processed) / Double(total) * 100))
    }

    func finish(success: Bool) {
        if let requestIdentifier {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: requestIdentifier)
            self.requestIdentifier = nil
        }
        if #available(iOS 26.0, *), let task = continuedTaskHandle as? BGContinuedProcessingTask {
            if success { task.progress.completedUnitCount = task.progress.totalUnitCount }
            task.setTaskCompleted(success: success)
        }
        continuedTaskHandle = nil
        endUIBackgroundTask()
    }
}
