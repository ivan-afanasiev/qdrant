#if os(iOS)
import BackgroundTasks
import Foundation
import UIKit
import SweepDomain

/// BackgroundTasks/UIKit adapter. Registers launch handlers, requests windows and wraps
/// system tasks as `ExecutionWindow`s that can be finished only once.
///
/// Info.plist must list `processingIdentifier` and `continuedIdentifierPrefix + ".*"` in
/// `BGTaskSchedulerPermittedIdentifiers` and include the `processing` background mode.
public final class BackgroundTaskScheduler: BackgroundExecutionScheduling, @unchecked Sendable {
    public static let processingIdentifier = "com.qdrant.edge.PhotoSweep.vectorization"
    public static let continuedIdentifierPrefix = "com.qdrant.edge.PhotoSweep.vectorization.continued"

    private let continuedTitle: String
    private let continuedSubtitle: String

    /// - Parameters: localized Live Activity texts shown for continued processing.
    public init(continuedTitle: String, continuedSubtitle: String) {
        self.continuedTitle = continuedTitle
        self.continuedSubtitle = continuedSubtitle
    }

    /// Must run before the app finishes launching. Windows are delivered to `handler`.
    /// Returns false if either registration was rejected (for example a missing plist entry).
    @MainActor
    @discardableResult
    public func registerLaunchHandlers(_ handler: @escaping @Sendable (any ExecutionWindow) -> Void) -> Bool {
        let processing = BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.processingIdentifier, using: nil) { task in
            guard let task = task as? BGProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handler(SystemTaskWindow(task: task, kind: .scheduled))
        }
        let continued = BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.continuedIdentifierPrefix + ".*", using: nil) { task in
            guard let task = task as? BGContinuedProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handler(SystemTaskWindow(task: task, kind: .continued))
        }
        return processing && continued
    }

    public func requestContinuedProcessing() async -> Bool {
        let request = BGContinuedProcessingTaskRequest(
            identifier: Self.continuedIdentifierPrefix + "." + UUID().uuidString,
            title: continuedTitle,
            subtitle: continuedSubtitle
        )
        // Start now or not at all; a queued request could start long after the person's action.
        request.strategy = .fail
        // Default resources: CPU only, as agreed for heat (no background GPU).
        do {
            try BGTaskScheduler.shared.submit(request)
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    public func scheduleProcessing() async -> Bool {
        let request = BGProcessingTaskRequest(identifier: Self.processingIdentifier)
        // iOS decides when; no external power or network requirement.
        request.requiresExternalPower = false
        request.requiresNetworkConnectivity = false
        do {
            try BGTaskScheduler.shared.submit(request)
            return true
        } catch {
            return false
        }
    }

    public func beginGraceWindow() async -> (any ExecutionWindow)? {
        await MainActor.run { GraceWindow.begin() }
    }
}

/// Wraps a BGProcessingTask or BGContinuedProcessingTask.
final class SystemTaskWindow: ExecutionWindow, @unchecked Sendable {
    let kind: ExecutionWindowKind
    private let task: BGTask
    private let lock = NSLock()
    private var isFinished = false

    init(task: BGTask, kind: ExecutionWindowKind) {
        self.task = task
        self.kind = kind
    }

    func onExpiration(_ handler: @escaping @Sendable () -> Void) {
        task.expirationHandler = handler
    }

    func reportProgress(_ progress: VectorizationProgress) {
        // Continued tasks must show progress or the system ends them first under pressure.
        guard let continued = task as? BGContinuedProcessingTask else { return }
        continued.progress.totalUnitCount = Int64(progress.total)
        continued.progress.completedUnitCount = Int64(progress.vectorized + progress.deferred)
    }

    func finish(success: Bool) {
        let shouldFinish = lock.withLock {
            guard !isFinished else { return false }
            isFinished = true
            return true
        }
        if shouldFinish {
            task.setTaskCompleted(success: success)
        }
    }
}

/// Short `beginBackgroundTask` grace period after backgrounding.
final class GraceWindow: ExecutionWindow, @unchecked Sendable {
    let kind = ExecutionWindowKind.grace
    private let lock = NSLock()
    private var identifier: UIBackgroundTaskIdentifier = .invalid
    private var expirationHandler: (@Sendable () -> Void)?
    private var isFinished = false

    @MainActor
    static func begin() -> GraceWindow? {
        let window = GraceWindow()
        let identifier = UIApplication.shared.beginBackgroundTask(withName: "PhotoSweep.vectorization") { [weak window] in
            window?.expireNow()
        }
        guard identifier != .invalid else { return nil }
        window.lock.withLock { window.identifier = identifier }
        return window
    }

    func onExpiration(_ handler: @escaping @Sendable () -> Void) {
        lock.withLock { expirationHandler = handler }
    }

    func reportProgress(_ progress: VectorizationProgress) {}

    func finish(success: Bool) {
        guard let identifier = takeIdentifier() else { return }
        Task { @MainActor in
            UIApplication.shared.endBackgroundTask(identifier)
        }
    }

    /// Called on the main thread by UIKit. The task must end before this returns, so the
    /// asynchronous interruption is started and the system task ended immediately.
    @MainActor
    private func expireNow() {
        let handler = lock.withLock { expirationHandler }
        handler?()
        if let identifier = takeIdentifier() {
            UIApplication.shared.endBackgroundTask(identifier)
        }
    }

    private func takeIdentifier() -> UIBackgroundTaskIdentifier? {
        lock.withLock {
            guard !isFinished, identifier != .invalid else { return nil }
            isFinished = true
            return identifier
        }
    }
}
#endif
