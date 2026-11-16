import Foundation

public enum ExecutionWindowKind: Equatable, Sendable {
    /// User-initiated continued processing (shows a system Live Activity with Cancel).
    case continued
    /// A processing window iOS grants at a time of its choosing.
    case scheduled
    /// A short grace period right after the app moves to the background.
    case grace
}

/// A system-granted time window for vectorization. Every window must be finished exactly
/// once; implementations ignore repeated `finish` calls.
public protocol ExecutionWindow: AnyObject, Sendable {
    var kind: ExecutionWindowKind { get }
    /// Installs the handler the system calls when the window ends early (time running out,
    /// or the person cancelling a continued task, which the system does not distinguish).
    func onExpiration(_ handler: @escaping @Sendable () -> Void)
    func reportProgress(_ progress: VectorizationProgress)
    func finish(success: Bool)
}

/// Requests execution windows from the system. Grants are never guaranteed.
public protocol BackgroundExecutionScheduling: Sendable {
    /// Requests continued processing for an explicit user action. The window arrives later
    /// through the registered launch handler. Returns false if the system rejected it.
    func requestContinuedProcessing() async -> Bool
    /// Asks iOS for a processing window at a time it chooses, replacing a pending request.
    @discardableResult
    func scheduleProcessing() async -> Bool
    /// Starts a short grace window, or nil if none is available.
    func beginGraceWindow() async -> (any ExecutionWindow)?
}

public enum NotificationPermission: Equatable, Sendable {
    case authorized
    case denied
    case notDetermined
}

/// Tells the person that photos are ready for review. Never claims groups were found:
/// discovery only runs in the foreground.
public protocol ReviewReadyNotifying: Sendable {
    func permission() async -> NotificationPermission
    func postReviewReady(unavailableCount: Int) async throws
}

/// Summary of the most recent completed vectorization pass.
public struct CompletedPass: Equatable, Sendable {
    public let id: VectorizationPassID
    public let kind: VectorizationPass.Kind
    public let progress: VectorizationProgress

    public init(id: VectorizationPassID, kind: VectorizationPass.Kind, progress: VectorizationProgress) {
        self.id = id
        self.kind = kind
        self.progress = progress
    }

    /// A pass that actually processed photos; an empty pass makes nothing newly ready.
    public var didWork: Bool { progress.total > 0 }
}
