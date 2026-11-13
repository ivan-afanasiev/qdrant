import Testing
import SweepFeatureState
import SweepTestSupport

/// Minimal reducer exercising each effect shape.
private struct CounterFeature: Reducer {
    struct State: Equatable {
        var count = 0
        var received: [Int] = []
    }

    enum Action: Equatable, Sendable {
        case increment
        case loadValue(Int)
        case replaceableLoad(Int)
        case stopReplaceable
        case valueLoaded(Int)
    }

    static let replaceableID = EffectID("counter.replaceable")
    let gate: AsyncGate

    func reduce(into state: inout State, action: Action) -> Effect<Action> {
        switch action {
        case .increment:
            state.count += 1
            return .none
        case .loadValue(let value):
            return .run { send in
                await send(.valueLoaded(value))
            }
        case .replaceableLoad(let value):
            return .run(id: Self.replaceableID, cancelInFlight: true) { [gate] send in
                await gate.wait()
                await send(.valueLoaded(value))
            }
        case .stopReplaceable:
            return .cancel(Self.replaceableID)
        case .valueLoaded(let value):
            state.received.append(value)
            return .none
        }
    }
}

@MainActor
@Suite struct StoreTests {
    @Test func reducerUpdatesStateSynchronously() {
        let store = Store(initialState: CounterFeature.State(), reducer: CounterFeature(gate: AsyncGate()))
        let task = store.send(.increment)
        #expect(store.state.count == 1)
        #expect(task.isEmpty)
    }

    @Test func effectResultIsFedBackThroughReducer() async {
        let store = Store(initialState: CounterFeature.State(), reducer: CounterFeature(gate: AsyncGate()))
        await store.send(.loadValue(7)).finish()
        #expect(store.state.received == [7])
        #expect(store.runningEffectCount == 0)
    }

    @Test func cancelInFlightDropsStaleResult() async {
        let gate = AsyncGate()
        let store = Store(initialState: CounterFeature.State(), reducer: CounterFeature(gate: gate))
        let first = store.send(.replaceableLoad(1))
        let second = store.send(.replaceableLoad(2))
        await gate.open()
        await first.finish()
        await second.finish()
        #expect(store.state.received == [2])
    }

    @Test func cancelEffectDropsItsResult() async {
        let gate = AsyncGate()
        let store = Store(initialState: CounterFeature.State(), reducer: CounterFeature(gate: gate))
        let load = store.send(.replaceableLoad(1))
        store.send(.stopReplaceable)
        await gate.open()
        await load.finish()
        #expect(store.state.received.isEmpty)
    }

    @Test func cancelAllEffectsStopsRunningWork() async {
        let gate = AsyncGate()
        let store = Store(initialState: CounterFeature.State(), reducer: CounterFeature(gate: gate))
        store.send(.replaceableLoad(1))
        store.cancelAllEffects()
        await gate.open()
        await store.finishAllEffects()
        #expect(store.state.received.isEmpty)
    }

    @Test func mergedEffectsAllRun() async {
        struct Merging: Reducer {
            func reduce(into state: inout [Int], action: Int) -> Effect<Int> {
                guard action == 0 else {
                    state.append(action)
                    return .none
                }
                return .merge(.run { send in await send(1) }, .run { send in await send(2) })
            }
        }
        let store = Store(initialState: [Int](), reducer: Merging())
        await store.send(0).finish()
        #expect(store.state.sorted() == [1, 2])
    }
}
