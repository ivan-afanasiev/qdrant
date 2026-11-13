import Foundation

/// Synchronous, deterministic state transition. Side effects are described by the
/// returned `Effect` and executed by the `Store`; reducers never perform I/O themselves.
public protocol Reducer<State, Action> {
    associatedtype State
    associatedtype Action: Sendable

    func reduce(into state: inout State, action: Action) -> Effect<Action>
}

/// Identifies a long-lived or replaceable effect so it can be cancelled.
public struct EffectID: Hashable, Sendable {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

/// Description of asynchronous work started after a reduction.
public struct Effect<Action: Sendable>: Sendable {
    enum Operation: Sendable {
        case run(id: EffectID?, cancelInFlight: Bool, body: @Sendable (Send<Action>) async -> Void)
        case cancel(EffectID)
    }

    let operations: [Operation]

    public static var none: Effect { Effect(operations: []) }

    /// Runs `body` in a new task. With `cancelInFlight`, running effects with the same ID
    /// are cancelled first. Actions sent after cancellation are dropped.
    public static func run(
        id: EffectID? = nil,
        cancelInFlight: Bool = false,
        _ body: @escaping @Sendable (Send<Action>) async -> Void
    ) -> Effect {
        Effect(operations: [.run(id: id, cancelInFlight: cancelInFlight, body: body)])
    }

    public static func cancel(_ id: EffectID) -> Effect {
        Effect(operations: [.cancel(id)])
    }

    public static func merge(_ effects: Effect...) -> Effect {
        Effect(operations: effects.flatMap(\.operations))
    }

    public var isNone: Bool { operations.isEmpty }
}

/// Delivers result actions back to the store on the main actor.
@MainActor
public struct Send<Action: Sendable>: Sendable {
    let deliver: @MainActor @Sendable (Action) -> Void

    init(_ deliver: @escaping @MainActor @Sendable (Action) -> Void) {
        self.deliver = deliver
    }

    /// Drops the action if the sending effect was cancelled, so stale results never reach state.
    public func callAsFunction(_ action: Action) {
        guard !Task.isCancelled else { return }
        deliver(action)
    }
}
