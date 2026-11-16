#if os(iOS)
import SwiftUI
import SweepDesignSystem
import SweepDomain
import SweepSystem

extension PhotoSweepComposition {
    /// Registers background launch handlers. Call from the app's initializer, before launch
    /// finishes. Windows that arrive before any UI bootstrap the same runtime.
    public func registerBackgroundHandlers() {
        guard let scheduler = adapters.services.scheduler as? BackgroundTaskScheduler else { return }
        let bootstrap = bootstrap
        scheduler.registerLaunchHandlers { window in
            Task { await bootstrap.deliver(window) }
        }
    }
}

/// Root of the rewrite UI: bootstraps the runtime, then routes scene phases to the
/// lifecycle coordinator. Views never run business work themselves.
public struct PhotoSweepRootView: View {
    private enum Phase {
        case loading
        case failed(BootstrapError)
        case ready(AppRuntime)
    }

    private let composition: PhotoSweepComposition
    @State private var phase: Phase = .loading
    @Environment(\.scenePhase) private var scenePhase

    public init(composition: PhotoSweepComposition) {
        self.composition = composition
    }

    public var body: some View {
        content
            .task { await start() }
            .onChange(of: scenePhase) { _, newPhase in
                guard case .ready(let runtime) = phase else { return }
                Task { await Self.route(newPhase, to: runtime) }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading:
            ProgressView(L10n.loading)
        case .failed:
            BootstrapFailedView { Task { await start() } }
        case .ready(let runtime):
            AppShellView(runtime: runtime)
        }
    }

    private func start() async {
        phase = .loading
        do {
            let runtime = try await composition.bootstrap.start()
            phase = .ready(runtime)
            if scenePhase == .active {
                await runtime.lifecycle.appDidBecomeActive()
            }
        } catch {
            phase = .failed(error)
        }
    }

    private static func route(_ phase: ScenePhase, to runtime: AppRuntime) async {
        switch phase {
        case .active: await runtime.lifecycle.appDidBecomeActive()
        case .background: await runtime.lifecycle.appDidEnterBackground()
        case .inactive: break
        @unknown default: break
        }
    }
}

/// Shown when local data cannot be opened; Retry runs bootstrap again.
struct BootstrapFailedView: View {
    let retry: () -> Void

    var body: some View {
        VStack(spacing: QSpacing.md) {
            QStatusIcon(QIcons.photoError, size: QSize.iconLarge, color: QColors.error)
            Text(L10n.bootstrapFailed)
                .font(QTypography.titleMedium)
                .multilineTextAlignment(.center)
            Button(L10n.retry, action: retry)
                .buttonStyle(.glassProminent)
        }
        .padding()
    }
}
#endif
