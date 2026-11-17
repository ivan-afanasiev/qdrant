#if os(iOS)
import SwiftUI
import SweepDesignSystem
import SweepDomain
import SweepFeatureState
import SweepLibraryFeature
import SweepOnboardingFeature
import SweepReviewFeature
import SweepSettingsFeature
import SweepUseCases

/// Onboarding until it is completed, then the main screen.
struct AppShellView: View {
    let runtime: AppRuntime
    @State private var preferences: Preferences?

    var body: some View {
        Group {
            if let preferences {
                if preferences.isOnboardingCompleted {
                    MainView(runtime: runtime)
                } else {
                    OnboardingContainer(runtime: runtime) {
                        Task { await reload() }
                    }
                }
            } else {
                ProgressView(L10n.loading)
            }
        }
        .task { await reload() }
    }

    private func reload() async {
        preferences = (try? await runtime.loadPreferences.execute()) ?? .defaults
    }
}

private struct OnboardingContainer: View {
    @State private var store: Store<OnboardingFeature>
    private let onCompleted: () -> Void

    init(runtime: AppRuntime, onCompleted: @escaping () -> Void) {
        _store = State(initialValue: runtime.makeOnboardingStore())
        self.onCompleted = onCompleted
    }

    var body: some View {
        OnboardingView(store: store)
            .onChange(of: store.state.isCompleted) { _, isCompleted in
                if isCompleted { onCompleted() }
            }
    }
}

/// Progress until the initial pass opens review; then the review area, with a compact
/// progress line while vectorization is still working.
struct MainView: View {
    private let runtime: AppRuntime
    @State private var libraryStore: Store<LibraryFeature>
    @State private var discovery: DiscoveryUpdate

    init(runtime: AppRuntime) {
        self.runtime = runtime
        _libraryStore = State(initialValue: runtime.makeLibraryStore())
        _discovery = State(initialValue: runtime.discovery.current)
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(Text(L10n.appTitle))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink {
                            SettingsScreen(runtime: runtime)
                        } label: {
                            Image(systemName: QIcons.settings)
                                .accessibilityLabel(Text(L10n.settings))
                        }
                    }
                }
        }
        .tint(QColors.primary)
        .task {
            for await update in runtime.discovery.updates() {
                discovery = update
            }
        }
        // Observe vectorization for the whole main screen, not only while a progress view is
        // visible: otherwise a pass started from Settings (rescan, date range) never reaches
        // the compact progress line above the cards.
        .onAppear { libraryStore.send(.onAppear) }
        .onDisappear { libraryStore.send(.onDisappear) }
    }

    @ViewBuilder
    private var content: some View {
        if discovery.status == .waitingForInitialPass {
            LibraryProgressView(store: libraryStore)
        } else {
            // The progress line is a top bar, so the cards still scroll under it and the
            // navigation bar.
            ReviewArea(runtime: runtime)
                .safeAreaBar(edge: .top) {
                    if libraryStore.state.isActive {
                        LibraryProgressView(store: libraryStore, isCompact: true)
                            .padding(.horizontal, QSpacing.md)
                    }
                }
        }
    }
}

/// Settings with its own store, created when the screen is shown.
struct SettingsScreen: View {
    @State private var store: Store<SettingsFeature>

    init(runtime: AppRuntime) {
        _store = State(initialValue: runtime.makeSettingsStore())
    }

    var body: some View {
        SettingsView(store: store)
    }
}

/// Card review for the current discovery revision.
struct ReviewArea: View {
    @State private var store: Store<ReviewFeature>
    private let images: ReviewImages

    init(runtime: AppRuntime) {
        _store = State(initialValue: runtime.makeReviewStore())
        images = runtime.reviewImages
    }

    var body: some View {
        ReviewView(store: store, images: images)
    }
}

private extension LibraryFeature.State {
    /// Statuses worth showing above the cards.
    var isActive: Bool {
        switch status {
        case .running, .pausedByUser, .failed: true
        case .idle, .interrupted, .completed: false
        }
    }
}
#endif
