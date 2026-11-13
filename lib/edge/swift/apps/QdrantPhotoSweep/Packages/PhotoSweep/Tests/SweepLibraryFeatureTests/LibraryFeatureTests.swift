import Testing
import SweepDomain
import SweepFeatureState
import SweepLibraryFeature

private actor ControlLog {
    private(set) var calls: [String] = []

    func record(_ call: String) {
        calls.append(call)
    }
}

@MainActor
private func makeStore(
    status: VectorizationStatus = .idle
) -> (Store<LibraryFeature>, AsyncStream<VectorizationStatus>.Continuation, ControlLog) {
    let (stream, continuation) = AsyncStream<VectorizationStatus>.makeStream()
    let log = ControlLog()
    let controls = VectorizationControls(
        observeStatus: { stream },
        pause: { await log.record("pause") },
        resume: { await log.record("resume") },
        retry: { await log.record("retry") }
    )
    let store = Store(initialState: LibraryFeature.State(status: status), reducer: LibraryFeature(controls: controls))
    return (store, continuation, log)
}

private let halfway = VectorizationProgress(total: 10, vectorized: 4, deferred: 1)

@MainActor
@Suite struct LibraryFeatureTests {
    @Test func observedStatusesReachState() async {
        let (store, continuation, _) = makeStore()
        let observation = store.send(.onAppear)
        #expect(store.state.isObserving)
        continuation.yield(.running(halfway))
        continuation.yield(.completed(deferredCount: 1))
        continuation.finish()
        await observation.finish()
        #expect(store.state.status == .completed(deferredCount: 1))
    }

    @Test func disappearingCancelsSubscriptionButNotVectorization() async {
        let (store, continuation, log) = makeStore(status: .running(halfway))
        let observation = store.send(.onAppear)
        store.send(.onDisappear)
        await observation.finish()
        continuation.yield(.completed(deferredCount: 0))
        #expect(store.state.status == .running(halfway))
        #expect(!store.state.isObserving)
        #expect(await log.calls.isEmpty)
    }

    @Test(arguments: [
        (VectorizationStatus.running(halfway), LibraryFeature.Control.pause, "pause"),
        (.pausedByUser(halfway), .resume, "resume"),
        (.failed(.systemic("store"), halfway), .retry, "retry"),
    ])
    func offeredControlInvokesOperation(status: VectorizationStatus, control: LibraryFeature.Control, call: String) async {
        let (store, _, log) = makeStore(status: status)
        #expect(store.state.control == control)
        await store.send(.controlTapped(control)).finish()
        #expect(await log.calls == [call])
        // State changes only through observed status, not optimistically.
        #expect(store.state.status == status)
    }

    @Test func staleControlTapIsIgnored() async {
        let (store, _, log) = makeStore(status: .running(halfway))
        let task = store.send(.controlTapped(.resume))
        #expect(task.isEmpty)
        #expect(await log.calls.isEmpty)
    }

    @Test(arguments: [VectorizationStatus.idle, .interrupted(halfway), .completed(deferredCount: 2)])
    func statusesWithoutUserControl(status: VectorizationStatus) {
        #expect(LibraryFeature.State(status: status).control == nil)
    }
}
