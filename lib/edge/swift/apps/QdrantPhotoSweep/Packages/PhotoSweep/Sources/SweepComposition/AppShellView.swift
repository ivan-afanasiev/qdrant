#if os(iOS)
import SwiftUI
import SweepDesignSystem
import SweepDomain
import SweepFeatureState
import SweepLibraryFeature
import SweepOnboardingFeature
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
        }
        .tint(QColors.primary)
        .task {
            for await update in runtime.discovery.updates() {
                discovery = update
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if discovery.status == .waitingForInitialPass {
            LibraryProgressView(store: libraryStore)
        } else {
            VStack(spacing: QSpacing.md) {
                if libraryStore.state.isActive {
                    LibraryProgressView(store: libraryStore, isCompact: true)
                        .padding(.horizontal, QSpacing.md)
                }
                ReviewArea(runtime: runtime)
            }
        }
    }
}

/// Card review; filled in by the review slice.
struct ReviewArea: View {
    let runtime: AppRuntime

    var body: some View {
        Spacer()
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
