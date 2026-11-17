import Foundation

public enum AssetOutcome: Equatable, Sendable {
    case pending
    case vectorized
    case deferred(DeferralReason)
}

public struct VectorizationProgress: Equatable, Sendable {
    public let total: Int
    public let vectorized: Int
    public let deferred: Int

    public init(total: Int, vectorized: Int, deferred: Int) {
        self.total = total
        self.vectorized = vectorized
        self.deferred = deferred
    }

    public var remaining: Int { total - vectorized - deferred }

    /// Whether vectorization is working right now (preparing or analyzing).
    public static func isWorking(_ status: VectorizationStatus) -> Bool {
        switch status {
        case .preparing, .running: true
        case .idle, .pausedByUser, .interrupted, .failed, .completed: false
        }
    }

    /// Progress over the whole scope: photos whose vectors were reused count as done.
    public func includingReused(_ reused: Int) -> VectorizationProgress {
        VectorizationProgress(total: total + reused, vectorized: vectorized + reused, deferred: deferred)
    }
    public var isComplete: Bool { remaining == 0 }
}

/// User-visible vectorization state. There is deliberately no cancelled state.
public enum VectorizationStatus: Equatable, Sendable {
    case idle
    /// Checking access and reading the library before photos are analyzed. `total` is 0
    /// until the library has been fetched; `done` counts photos registered so far.
    case preparing(done: Int, total: Int)
    case running(VectorizationProgress)
    case pausedByUser(VectorizationProgress)
    /// Stopped by the system (expiration, termination); resumes without user action.
    case interrupted(VectorizationProgress)
    case failed(VectorizationStopReason, VectorizationProgress)
    case completed(deferredCount: Int)
}

/// One pass over a captured work set. An initial pass gates discovery;
/// incremental passes handle later arrivals and never close the gate.
public struct VectorizationPass: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case initial
        case incremental
    }

    public let id: VectorizationPassID
    public let kind: Kind
    public let scope: DateRange
    public private(set) var outcomes: [AssetID: AssetOutcome]

    public init(id: VectorizationPassID, kind: Kind, scope: DateRange, workSet: [AssetID]) {
        self.id = id
        self.kind = kind
        self.scope = scope
        self.outcomes = Dictionary(workSet.map { ($0, AssetOutcome.pending) }, uniquingKeysWith: { first, _ in first })
    }

    /// Restores a persisted pass with its recorded outcomes.
    public init(id: VectorizationPassID, kind: Kind, scope: DateRange, outcomes: [AssetID: AssetOutcome]) {
        self.id = id
        self.kind = kind
        self.scope = scope
        self.outcomes = outcomes
    }

    /// Records an outcome for an asset in the captured work set.
    /// Returns false for assets outside the work set, which belong to a later pass.
    @discardableResult
    public mutating func record(_ outcome: AssetOutcome, for asset: AssetID) -> Bool {
        guard outcomes[asset] != nil else { return false }
        outcomes[asset] = outcome
        return true
    }

    public var progress: VectorizationProgress {
        var vectorized = 0
        var deferred = 0
        for outcome in outcomes.values {
            switch outcome {
            case .pending: break
            case .vectorized: vectorized += 1
            case .deferred: deferred += 1
            }
        }
        return VectorizationProgress(total: outcomes.count, vectorized: vectorized, deferred: deferred)
    }

    /// Every asset is vectorized or explicitly deferred.
    public var isComplete: Bool { progress.isComplete }

    /// Pending assets in a stable order.
    public var pendingAssets: [AssetID] {
        outcomes.filter { $0.value == .pending }.keys.sorted()
    }
}

/// Discovery may start only after the initial pass for the current scope completes.
/// Later incremental passes never reopen it; scope changes and rescans start a new initial pass.
public struct InitialPassGate: Equatable, Sendable {
    public enum State: Equatable, Sendable {
        case awaitingInitialPass(VectorizationPassID?)
        case open(deferredCount: Int)
    }

    public private(set) var state: State

    public init(state: State = .awaitingInitialPass(nil)) {
        self.state = state
    }

    public var isOpen: Bool {
        if case .open = state { return true }
        return false
    }

    /// Closes the gate for a new scoped pass (date-scope change or explicit rescan).
    public mutating func beginInitialPass(_ id: VectorizationPassID) {
        state = .awaitingInitialPass(id)
    }

    /// Opens the gate only for the completed initial pass it is waiting for.
    public mutating func passFinished(_ pass: VectorizationPass) {
        guard pass.kind == .initial, pass.isComplete,
              case .awaitingInitialPass(let awaited) = state, awaited == pass.id else { return }
        state = .open(deferredCount: pass.progress.deferred)
    }
}
