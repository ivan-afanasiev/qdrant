import Foundation
import SweepDomain
import SweepFeatureState
import SweepLibraryFeature
import SweepOnboardingFeature
import SweepReviewFeature
import SweepSettingsFeature
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
    public func makeReviewStore() -> Store<ReviewFeature> {
        let discovery = discovery
        let finisher = FinishConfirmedDeletion(assets: store, vectorStores: services.vectorStores, workflow: store, deletion: store)
        let refill: QueueChangeHandler = { await discovery.requestRefill() }
        let client = ReviewClient.live(
            discovery: discovery,
            loadNext: LoadNextReviewGroup(review: store, progress: store, workflow: store, journal: store),
            skip: SkipGroup(review: store, onQueueChanged: refill),
            commit: CommitReviewDecision(review: store, journal: store, library: services.library, finisher: finisher, onQueueChanged: refill),
            ids: ids
        )
        return Store(initialState: ReviewFeature.State(discovery: discovery.current), reducer: ReviewFeature(client: client))
    }

    public var reviewImages: ReviewImages {
        let images = LoadReviewImage(library: services.library)
        return ReviewImages(
            details: { await images.details($0) },
            thumbnail: { try? await images.thumbnail($0, pixels: $1) },
            original: { try? await images.original($0) }
        )
    }

    @MainActor
    public func makeSettingsStore() -> Store<SettingsFeature> {
        let load = loadPreferences
        let statistics = LoadStatistics(statistics: store)
        let updateDateScope = UpdateDateScope(workflow: store, discovery: discovery, lifecycle: lifecycle)
        let updateSimilarity = UpdateSimilarityThreshold(workflow: store, discovery: discovery)
        let rescan = RescanLibrary(workflow: store, discovery: discovery, lifecycle: lifecycle)
        let reset = ResetAppData(
            workflow: store, resetting: store, vectorStores: services.vectorStores,
            vectorization: vectorization, discovery: discovery, lifecycle: lifecycle, ids: ids
        )
        return Store(initialState: SettingsFeature.State(), reducer: SettingsFeature(client: SettingsClient(
            loadPreferences: { try? await load.execute() },
            loadStatistics: { try? await statistics.execute() },
            updateDateScope: { (try? await updateDateScope.execute($0)) != nil },
            updateSimilarity: { (try? await updateSimilarity.execute($0)) != nil },
            rescan: { (try? await rescan.execute()) != nil },
            reset: { (try? await reset.execute()) != nil }
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
