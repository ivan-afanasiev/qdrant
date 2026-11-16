import Foundation
import SweepDomain
import SweepFeatureState
import SweepLibraryFeature
import SweepOnboardingFeature
import SweepUseCases

/// Feature stores receive app-owned use cases from the runtime; each screen gets its own
/// store and subscriptions, while vectorization and discovery stay app-scoped.
extension AppRuntime {
    public var loadPreferences: LoadPreferences {
        LoadPreferences(workflow: store)
    }

    @MainActor
    public func makeOnboardingStore() -> Store<OnboardingFeature> {
        let requestAccess = RequestPhotoAccess(library: services.library)
        let requestNotifications = RequestNotificationPermission(notifier: services.notifier)
        let runtime = self
        let complete = CompleteOnboarding(workflow: store, lifecycle: lifecycle) {
            await runtime.observeLibraryChangesIfAuthorized()
        }
        return Store(initialState: OnboardingFeature.State(), reducer: OnboardingFeature(client: OnboardingClient(
            requestPhotoAccess: { await requestAccess.execute() },
            requestNotifications: { await requestNotifications.execute() },
            complete: { preset in
                do {
                    try await complete.execute(datePreset: preset)
                    return true
                } catch {
                    return false
                }
            }
        )))
    }

    @MainActor
    public func makeLibraryStore() -> Store<LibraryFeature> {
        let vectorization = vectorization
        let lifecycle = lifecycle
        return Store(initialState: LibraryFeature.State(status: vectorization.status), reducer: LibraryFeature(controls: VectorizationControls(
            observeStatus: { vectorization.statusUpdates() },
            pause: { await vectorization.pause() },
            // Resume and Retry are the person's actions, so they may continue in the background.
            resume: { await lifecycle.userRequestedVectorization(.userResume) },
            retry: { await lifecycle.userRequestedVectorization(.userRetry) }
        )))
    }
}
