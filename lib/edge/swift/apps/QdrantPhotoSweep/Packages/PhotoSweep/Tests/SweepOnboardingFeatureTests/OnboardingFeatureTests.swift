import Testing
import SweepDomain
import SweepFeatureState
import SweepOnboardingFeature

private actor OnboardingLog {
    private(set) var completedWith: [DateScopePreset] = []

    func complete(_ preset: DateScopePreset) {
        completedWith.append(preset)
    }
}

@MainActor
private func makeStore(
    access: PhotoAccessScope = .full,
    notifications: Bool = true,
    completes: Bool = true
) -> (Store<OnboardingFeature>, OnboardingLog) {
    let log = OnboardingLog()
    let client = OnboardingClient(
        requestPhotoAccess: { access },
        requestNotifications: { notifications },
        complete: { preset in
            await log.complete(preset)
            return completes
        }
    )
    return (Store(initialState: OnboardingFeature.State(), reducer: OnboardingFeature(client: client)), log)
}

@MainActor
@Suite struct OnboardingFeatureTests {
    @Test func walksThroughEveryStepAndStartsWithChosenPreset() async {
        let (store, log) = makeStore()
        store.send(.continueTapped)
        #expect(store.state.step == .photoAccess)
        await store.send(.allowPhotosTapped).finish()
        #expect(store.state.step == .notifications)
        await store.send(.allowNotificationsTapped).finish()
        #expect(store.state.step == .dateRange)
        #expect(store.state.datePreset == .last3Years)

        store.send(.datePresetSelected(.last5Years))
        await store.send(.startTapped).finish()
        #expect(store.state.isCompleted)
        #expect(await log.completedWith == [.last5Years])
    }

    @Test func deniedAccessStaysOnAccessStep() async {
        let (store, _) = makeStore(access: .none)
        store.send(.continueTapped)
        await store.send(.allowPhotosTapped).finish()
        #expect(store.state.step == .photoAccess)
        #expect(store.state.isAccessDenied)
    }

    @Test func limitedAccessIsEnoughToContinue() async {
        let (store, _) = makeStore(access: .limited)
        store.send(.continueTapped)
        await store.send(.allowPhotosTapped).finish()
        #expect(store.state.step == .notifications)
        #expect(!store.state.isAccessDenied)
    }

    @Test func declinedOrSkippedNotificationsStillContinue() async {
        let (declined, _) = makeStore(notifications: false)
        declined.send(.continueTapped)
        await declined.send(.allowPhotosTapped).finish()
        await declined.send(.allowNotificationsTapped).finish()
        #expect(declined.state.step == .dateRange)

        let (skipped, _) = makeStore()
        skipped.send(.continueTapped)
        await skipped.send(.allowPhotosTapped).finish()
        skipped.send(.skipNotificationsTapped)
        #expect(skipped.state.step == .dateRange)
    }

    @Test func failedCompletionCanBeRetried() async {
        let (store, log) = makeStore(completes: false)
        store.send(.continueTapped)
        await store.send(.allowPhotosTapped).finish()
        store.send(.skipNotificationsTapped)
        await store.send(.startTapped).finish()
        #expect(!store.state.isCompleted)
        #expect(store.state.didFailToComplete)
        await store.send(.startTapped).finish()
        #expect(await log.completedWith.count == 2)
    }

    @Test func outOfOrderActionsAreIgnored() {
        let (store, _) = makeStore()
        #expect(store.send(.startTapped).isEmpty)
        #expect(store.send(.allowPhotosTapped).isEmpty)
        store.send(.backTapped)
        #expect(store.state.step == .welcome)
    }
}
