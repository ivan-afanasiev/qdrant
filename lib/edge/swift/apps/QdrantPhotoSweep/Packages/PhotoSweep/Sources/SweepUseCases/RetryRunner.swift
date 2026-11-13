import SweepDomain

public enum RetryRunOutcome<Value: Sendable>: Sendable {
    case succeeded(Value, attempts: Int)
    /// The asset stayed unavailable; record it as deferred and continue the pass.
    case deferred(DeferralReason, attempts: Int)
    /// The pass must stop and expose Retry.
    case stopped(VectorizationStopReason, attempts: Int)
}

extension RetryRunOutcome: Equatable where Value: Equatable {}

/// Runs one unit of vectorization work under the finite `RetryPolicy`.
/// Waiting goes through the injected `Sleeper`, so tests never depend on real time.
public struct RetryRunner: Sendable {
    private let policy: RetryPolicy
    private let sleeper: any Sleeper

    public init(policy: RetryPolicy, sleeper: any Sleeper) {
        self.policy = policy
        self.sleeper = sleeper
    }

    /// - Throws: `CancellationError` when the surrounding task is cancelled;
    ///   the caller keeps its checkpoint so the work can resume later.
    public func run<Value: Sendable>(
        _ operation: () async throws(VectorizationFailure) -> Value
    ) async throws(CancellationError) -> RetryRunOutcome<Value> {
        var attempt = 1
        while true {
            if Task.isCancelled { throw CancellationError() }
            let failure: VectorizationFailure
            do {
                return .succeeded(try await operation(), attempts: attempt)
            } catch {
                failure = error
            }
            switch policy.decide(failure, attempt: attempt) {
            case .retry(let delay):
                do {
                    try await sleeper.sleep(for: delay)
                } catch {
                    throw CancellationError()
                }
                attempt += 1
            case .deferAsset(let reason):
                return .deferred(reason, attempts: attempt)
            case .stopPass(let reason):
                return .stopped(reason, attempts: attempt)
            }
        }
    }
}
