import Testing
import SweepDomain
import SweepFeatureState
import SweepSettingsFeature
import SweepUseCases

private actor SettingsBackend {
    private(set) var calls: [String] = []
    private(set) var loads = 0
    var preferences = Preferences(datePreset: .allTime, similarity: .balanced, isOnboardingCompleted: true)
    var succeeds = true

    func setSucceeds(_ value: Bool) {
        succeeds = value
    }

    func load() -> Preferences {
        loads += 1
        return preferences
    }

    func record(_ call: String) -> Bool {
        calls.append(call)
        return succeeds
    }
}

private let stats = LibraryStatistics(vectorizedPhotos: 10, unavailablePhotos: 1, reviewedGroups: 2, deletedPhotos: 3, estimatedBytesFreed: 4_000, deletionsWithUnknownSize: 1)

@MainActor
private func makeStore() -> (Store<SettingsFeature>, SettingsBackend) {
    let backend = SettingsBackend()
    let client = SettingsClient(
        loadPreferences: { await backend.load() },
        loadStatistics: { stats },
        updateDateScope: { await backend.record("date:\($0.rawValue)") },
        updateSimilarity: { await backend.record("similarity:\($0.rawValue)") },
        rescan: { await backend.record("rescan") },
        reset: { await backend.record("reset") }
    )
    return (Store(initialState: SettingsFeature.State(), reducer: SettingsFeature(client: client)), backend)
}

@MainActor
@Suite struct SettingsFeatureTests {
    @Test func loadsPreferencesAndStatistics() async {
        let (store, _) = makeStore()
        await store.send(.onAppear).finish()
        #expect(store.state.preferences?.similarity == .balanced)
        #expect(store.state.statistics == stats)
    }

    @Test func changesGoThroughUseCasesAndReload() async {
        let (store, backend) = makeStore()
        await store.send(.onAppear).finish()
        store.send(.similaritySelected(.strict))
        store.send(.datePresetSelected(.lastYear))
        await store.finishAllEffects()
        store.send(.rescanTapped)
        await store.finishAllEffects()
        #expect(await backend.calls == ["similarity:strict", "rescan"])
        #expect(await backend.loads >= 3)
    }

    @Test func selectingCurrentValuesDoesNothing() async {
        let (store, backend) = makeStore()
        await store.send(.onAppear).finish()
        #expect(store.send(.similaritySelected(.balanced)).isEmpty)
        #expect(store.send(.datePresetSelected(.allTime)).isEmpty)
        #expect(await backend.calls.isEmpty)
    }

    @Test func resetRequiresConfirmation() async {
        let (store, backend) = makeStore()
        #expect(store.send(.resetConfirmed).isEmpty)
        store.send(.resetTapped)
        #expect(store.state.isConfirmingReset)
        store.send(.resetCancelled)
        #expect(!store.state.isConfirmingReset)
        #expect(await backend.calls.isEmpty)

        store.send(.resetTapped)
        store.send(.resetConfirmed)
        await store.finishAllEffects()
        #expect(await backend.calls == ["reset"])
    }

    @Test func failureIsShownAndDismissable() async {
        let (store, backend) = makeStore()
        await backend.setSucceeds(false)
        store.send(.rescanTapped)
        await store.finishAllEffects()
        #expect(store.state.didFail)
        #expect(!store.state.isWorking)
        store.send(.failureDismissed)
        #expect(!store.state.didFail)
    }
}
