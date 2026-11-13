import Foundation

/// What asked vectorization to run.
public enum VectorizationTrigger: Equatable, Sendable {
    /// The app was opened or returned to the foreground.
    case appActivation
    /// Automatic foreground work such as new or changed photos.
    case automaticForeground
    /// Continuing foreground work after the app moves to the background.
    case backgroundContinuation
    /// Work started by an iOS-scheduled background opportunity.
    case backgroundScheduled
    case userResume
    case userRetry
}

public struct PauseState: Equatable, Sendable {
    public let isPausedByUser: Bool

    public init(isPausedByUser: Bool) {
        self.isPausedByUser = isPausedByUser
    }

    public static let none = PauseState(isPausedByUser: false)
    public static let manual = PauseState(isPausedByUser: true)
}

public enum VectorizationRunDecision: Equatable, Sendable {
    /// Run; `pause` is the state to persist before starting.
    case run(pause: PauseState)
    case blockedByManualPause
}

/// Manual Pause blocks automatic foreground and background work until Resume or the
/// next app opening. System interruption is not a manual pause and never reaches here as one.
public enum PausePolicy {
    public static func decide(_ trigger: VectorizationTrigger, current: PauseState) -> VectorizationRunDecision {
        switch trigger {
        case .appActivation, .userResume, .userRetry:
            .run(pause: .none)
        case .automaticForeground, .backgroundContinuation, .backgroundScheduled:
            current.isPausedByUser ? .blockedByManualPause : .run(pause: current)
        }
    }
}
