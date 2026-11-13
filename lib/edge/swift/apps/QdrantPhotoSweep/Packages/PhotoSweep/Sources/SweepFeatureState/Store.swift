import Foundation
import Observation

/// Main-actor owner of feature state and its effect tasks.
/// Views read `state` and call `send`; only the reducer mutates state.
@MainActor
@Observable
public final class Store<R: Reducer> {
    public private(set) var state: R.State

    @ObservationIgnored private let reducer: R
    @ObservationIgnored private var running: [UUID: RunningEffect] = [:]

    public init(initialState: R.State, reducer: R) {
        self.state = initialState
        self.reducer = reducer
    }

    deinit {
        for effect in running.values {
            effect.task.cancel()
        }
    }

    /// Reduces the action and starts its effects.
    /// The returned handle lets callers (mainly tests) await or cancel those effects.
    @discardableResult
    public func send(_ action: R.Action) -> StoreTask {
        let effect = reducer.reduce(into: &state, action: action)
        return start(effect)
    }

    /// Cancels every running effect, for example when the owning screen goes away.
    public func cancelAllEffects() {
        for effect in running.values {
            effect.task.cancel()
        }
    }

    /// Number of effects that have not finished yet.
    public var runningEffectCount: Int { running.count }

    /// Waits until no effects are running, including effects started by sent actions.
    /// Do not use while an unbounded observation effect is active.
    public func finishAllEffects() async {
        while let effect = running.values.first {
            await effect.task.value
        }
    }

    private func start(_ effect: Effect<R.Action>) -> StoreTask {
        var tasks: [Task<Void, Never>] = []
        for operation in effect.operations {
            switch operation {
            case .cancel(let id):
                cancel(id)
            case .run(let id, let cancelInFlight, let body):
                if let id, cancelInFlight {
                    cancel(id)
                }
                let token = UUID()
                let send = Send<R.Action> { [weak self] action in
                    self?.send(action)
                }
                // The task inherits the main actor, so it cannot start before it is registered.
                let task = Task { [weak self] in
                    await body(send)
                    self?.running[token] = nil
                }
                running[token] = RunningEffect(id: id, task: task)
                tasks.append(task)
            }
        }
        return StoreTask(tasks: tasks)
    }

    private func cancel(_ id: EffectID) {
        for effect in running.values where effect.id == id {
            effect.task.cancel()
        }
    }
}

private struct RunningEffect: Sendable {
    let id: EffectID?
    let task: Task<Void, Never>
}

/// Handle to the effects started by one `send`.
public struct StoreTask: Sendable {
    let tasks: [Task<Void, Never>]

    public var isEmpty: Bool { tasks.isEmpty }

    public func finish() async {
        for task in tasks {
            await task.value
        }
    }

    public func cancel() {
        for task in tasks {
            task.cancel()
        }
    }
}
