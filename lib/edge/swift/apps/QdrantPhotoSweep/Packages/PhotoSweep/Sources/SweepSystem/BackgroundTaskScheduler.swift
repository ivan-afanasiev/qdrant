#if os(iOS)
import BackgroundTasks
import Foundation
import os
import UIKit
import SweepDomain

/// BackgroundTasks/UIKit adapter. Registers launch handlers, requests windows and wraps
/// system tasks as `ExecutionWindow`s that can be finished only once.
///
/// Info.plist must list `processingIdentifier` and `continuedIdentifierPrefix + ".*"` in
/// `BGTaskSchedulerPermittedIdentifiers` and include the `processing` background mode.
///
/// The `.*` entry is a pattern only: iOS rejects registering the wildcard itself ("not
/// advertised in the application's Info.plist"). Each continued request instead registers its
/// own concrete identifier (`prefix.<UUID>`) right before submitting it, as in Apple's
/// "Performing long-running tasks" sample. Verified on the iOS 26.5 simulator.
public final class BackgroundTaskScheduler: BackgroundExecutionScheduling, @unchecked Sendable {
    // Continued-processing identifiers must start with the app's bundle ID
    // (`com.qdrant.edge.QdrantPhotoSweep`), or iOS rejects them as an invalid form.
    public static let processingIdentifier = "com.qdrant.edge.QdrantPhotoSweep.scheduledVectorization"
    public static let continuedIdentifierPrefix = "com.qdrant.edge.QdrantPhotoSweep.continuedVectorization"

    private let continuedTitle: String
    private let continuedSubtitle: String
    /// Whether iOS accepted the processing handler, and the handler for continued windows.
    /// Submitting a request without a registered handler terminates the app, so requests are
    /// only made after a successful registration.
    private let isProcessingRegistered = OSAllocatedUnfairLock(initialState: false)
    private let continuedHandler = OSAllocatedUnfairLock<(@Sendable (any ExecutionWindow) -> Void)?>(initialState: nil)
    private let logger = Logger(subsystem: "com.qdrant.edge.QdrantPhotoSweep", category: "background")

    /// - Parameters: localized Live Activity texts shown for continued processing.
    public init(continuedTitle: String, continuedSubtitle: String) {
        self.continuedTitle = continuedTitle
        self.continuedSubtitle = continuedSubtitle
    }

    /// Must run before the app finishes launching. Windows are delivered to `handler`.
    /// Returns false if the processing registration was rejected (for example a missing plist
    /// entry). Continued windows register per request in `requestContinuedProcessing()`.
    @MainActor
    @discardableResult
    public func registerLaunchHandlers(_ handler: @escaping @Sendable (any ExecutionWindow) -> Void) -> Bool {
        let processing = BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.processingIdentifier, using: nil,
            launchHandler: Self.launchHandler(kind: .scheduled, deliver: handler)
        )
        isProcessingRegistered.withLock { $0 = processing }
        continuedHandler.withLock { $0 = handler }
        if !processing {
            logger.error("Processing task registration rejected; scheduled background work is off")
        }
        return processing
    }

    /// iOS calls launch handlers on its own background queue. A closure written inside a
    /// `@MainActor` method is main-actor isolated in Swift 6, and running it there trips the
    /// runtime isolation check (EXC_BREAKPOINT on the BGTask queue). Building the handler in
    /// this nonisolated function keeps it free of any actor.
    private nonisolated static func launchHandler(
        kind: ExecutionWindowKind,
        deliver: @escaping @Sendable (any ExecutionWindow) -> Void
    ) -> @Sendable (BGTask) -> Void {
        { task in
            let expectedType = switch kind {
            case .continued: task is BGContinuedProcessingTask
            case .scheduled: task is BGProcessingTask
            case .grace: false
            }
            guard expectedType else {
                task.setTaskCompleted(success: false)
                return
            }
            deliver(SystemTaskWindow(task: task, kind: kind))
        }
    }

    public func requestContinuedProcessing() async -> Bool {
        guard let handler = continuedHandler.withLock({ $0 }) else { return false }
        return await MainActor.run { submitContinued(handler: handler) }
    }

    @MainActor
    private func submitContinued(handler: @escaping @Sendable (any ExecutionWindow) -> Void) -> Bool {
        let identifier = Self.continuedIdentifierPrefix + "." + UUID().uuidString
        let registered = BGTaskScheduler.shared.register(
            forTaskWithIdentifier: identifier, using: nil,
            launchHandler: Self.launchHandler(kind: .continued, deliver: handler)
        )
        guard registered else {
            logger.error("Continued task registration rejected for \(identifier, privacy: .public)")
            return false
        }
        let request = BGContinuedProcessingTaskRequest(
            identifier: identifier,
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
            logger.notice("Continued processing not started: \(String(describing: error), privacy: .public)")
            return false
        }
    }

    @discardableResult
    public func scheduleProcessing() async -> Bool {
        guard isProcessingRegistered.withLock({ $0 }) else { return false }
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
