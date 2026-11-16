import Foundation
import SweepDomain

/// Execution window that records what the coordinator does with it.
public final class FakeExecutionWindow: ExecutionWindow, @unchecked Sendable {
    public let kind: ExecutionWindowKind
    private let lock = NSLock()
    private var expirationHandler: (@Sendable () -> Void)?
    private var reported: [VectorizationProgress] = []
    private var finishes: [Bool] = []
    private var finishWaiters: [CheckedContinuation<Void, Never>] = []
    private var progressWaiters: [CheckedContinuation<Void, Never>] = []
    private var registrationWaiters: [CheckedContinuation<Void, Never>] = []

    public init(kind: ExecutionWindowKind) {
        self.kind = kind
    }

    public func onExpiration(_ handler: @escaping @Sendable () -> Void) {
        let waiters = lock.withLock {
            expirationHandler = handler
            let waiters = registrationWaiters
            registrationWaiters.removeAll()
            return waiters
        }
        waiters.forEach { $0.resume() }
    }

    /// Suspends until a coordinator has taken charge of the window (installed its handler).
    public func waitUntilRegistered() async {
        await withCheckedContinuation { continuation in
            let registered = lock.withLock {
                if expirationHandler == nil {
                    registrationWaiters.append(continuation)
                    return false
                }
                return true
            }
            if registered {
                continuation.resume()
            }
        }
    }

    public func reportProgress(_ progress: VectorizationProgress) {
        let waiters = lock.withLock {
            reported.append(progress)
            let waiters = progressWaiters
            progressWaiters.removeAll()
            return waiters
        }
        waiters.forEach { $0.resume() }
    }

    /// Suspends until at least one progress report arrived.
    public func waitForProgress() async {
        await withCheckedContinuation { continuation in
            let alreadyReported = lock.withLock {
                if reported.isEmpty {
                    progressWaiters.append(continuation)
                    return false
                }
                return true
            }
            if alreadyReported {
                continuation.resume()
            }
        }
    }

    public func finish(success: Bool) {
        let waiters = lock.withLock {
            finishes.append(success)
            let waiters = finishWaiters
            finishWaiters.removeAll()
            return waiters
        }
        waiters.forEach { $0.resume() }
    }

    /// Simulates the system ending the window early.
    public func expire() {
        let handler = lock.withLock { expirationHandler }
        handler?()
    }

    /// Every `finish` call, so tests can assert exactly-once completion.
    public var finishCalls: [Bool] { lock.withLock { finishes } }
    public var reportedProgress: [VectorizationProgress] { lock.withLock { reported } }
    public var hasExpirationHandler: Bool { lock.withLock { expirationHandler != nil } }

    /// Suspends until the window has been finished at least once.
    public func waitUntilFinished() async {
        await withCheckedContinuation { continuation in
            let alreadyFinished = lock.withLock {
                if finishes.isEmpty {
                    finishWaiters.append(continuation)
                    return false
                }
                return true
            }
            if alreadyFinished {
                continuation.resume()
            }
        }
    }
}

/// Scheduler that records requests and hands out grace windows.
public actor FakeBackgroundScheduler: BackgroundExecutionScheduling {
    public private(set) var continuedRequests = 0
    public private(set) var processingRequests = 0
    public private(set) var graceWindows: [FakeExecutionWindow] = []
    public private(set) var acceptsContinuedProcessing = true
    public private(set) var providesGraceWindow = true

    public init() {}

    public func setAcceptsContinuedProcessing(_ value: Bool) {
        acceptsContinuedProcessing = value
    }

    public func setProvidesGraceWindow(_ value: Bool) {
        providesGraceWindow = value
    }

    public func requestContinuedProcessing() async -> Bool {
        continuedRequests += 1
        return acceptsContinuedProcessing
    }

    @discardableResult
    public func scheduleProcessing() async -> Bool {
        processingRequests += 1
        return true
    }

    public func beginGraceWindow() async -> (any ExecutionWindow)? {
        guard providesGraceWindow else { return nil }
        let window = FakeExecutionWindow(kind: .grace)
        graceWindows.append(window)
        return window
    }
}

/// Notifier that records posted notifications.
public actor FakeReviewNotifier: ReviewReadyNotifying {
    public private(set) var posted: [Int] = []
    public private(set) var currentPermission: NotificationPermission

    public init(permission: NotificationPermission = .authorized) {
        currentPermission = permission
    }

    public func setPermission(_ permission: NotificationPermission) {
        currentPermission = permission
    }

    public func permission() async -> NotificationPermission {
        currentPermission
    }

    public func postReviewReady(unavailableCount: Int) async throws {
        posted.append(unavailableCount)
    }
}
