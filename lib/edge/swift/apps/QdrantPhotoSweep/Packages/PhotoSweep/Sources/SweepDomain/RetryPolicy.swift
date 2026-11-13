import Foundation

/// Classified vectorization failure. Retrying one photo differs from retrying a broken store or model.
public enum VectorizationFailure: Error, Equatable, Sendable {
    /// Infrastructure hiccup not attributable to the asset (store busy, I/O).
    case transient(String)
    /// This asset could not be loaded or embedded (iCloud download, corrupt data).
    case assetUnavailable(String)
    /// Library access was lost or reduced.
    case authorization
    /// Stored vectors cannot be compared with the current model; needs a generation transition.
    case incompatibleEmbedding(String)
    /// Store or model failure that affects every asset.
    case systemic(String)
}

public enum DeferralReason: Equatable, Sendable {
    /// The asset stayed unavailable after the applicable attempts.
    case unavailable(String)
}

public enum VectorizationStopReason: Equatable, Sendable {
    case systemic(String)
    case authorization
    case incompatibleEmbedding(String)
}

public enum RetryDecision: Equatable, Sendable {
    case retry(after: Duration)
    case deferAsset(DeferralReason)
    case stopPass(VectorizationStopReason)
}

/// Finite retry policy. Attempt limits and delays are validation parameters,
/// not product decisions; tune them from device measurements.
public struct RetryPolicy: Equatable, Sendable {
    public let maxAssetAttempts: Int
    public let maxSystemicAttempts: Int
    public let baseDelay: Duration
    public let maxDelay: Duration

    public static let `default` = RetryPolicy(
        maxAssetAttempts: 3,
        maxSystemicAttempts: 3,
        baseDelay: .seconds(1),
        maxDelay: .seconds(30)
    )

    public init(maxAssetAttempts: Int, maxSystemicAttempts: Int, baseDelay: Duration, maxDelay: Duration) {
        precondition(maxAssetAttempts >= 1 && maxSystemicAttempts >= 1, "At least one attempt is required")
        self.maxAssetAttempts = maxAssetAttempts
        self.maxSystemicAttempts = maxSystemicAttempts
        self.baseDelay = baseDelay
        self.maxDelay = maxDelay
    }

    /// - Parameter attempt: 1-based number of the attempt that just failed.
    public func decide(_ failure: VectorizationFailure, attempt: Int) -> RetryDecision {
        switch failure {
        case .assetUnavailable(let detail):
            attempt < maxAssetAttempts ? .retry(after: delay(afterAttempt: attempt)) : .deferAsset(.unavailable(detail))
        case .transient(let detail), .systemic(let detail):
            // Infrastructure failures stop the pass instead of mislabeling photos as unavailable.
            attempt < maxSystemicAttempts ? .retry(after: delay(afterAttempt: attempt)) : .stopPass(.systemic(detail))
        case .authorization:
            .stopPass(.authorization)
        case .incompatibleEmbedding(let detail):
            .stopPass(.incompatibleEmbedding(detail))
        }
    }

    /// Exponential backoff capped at `maxDelay`.
    public func delay(afterAttempt attempt: Int) -> Duration {
        var delay = baseDelay
        for _ in 1..<max(attempt, 1) {
            delay *= 2
            if delay >= maxDelay { return maxDelay }
        }
        return min(delay, maxDelay)
    }
}

/// Suspends the caller. Inject a recording implementation in tests instead of real time.
public protocol Sleeper: Sendable {
    func sleep(for duration: Duration) async throws
}

public struct TaskSleeper: Sleeper {
    public init() {}

    public func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }
}
