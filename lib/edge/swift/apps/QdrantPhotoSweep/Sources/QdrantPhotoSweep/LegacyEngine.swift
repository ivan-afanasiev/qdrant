import Photos
import SwiftData
import SwiftUI

/// The pre-rewrite engine, kept selectable for testing until cutover (step 10).
/// Created only when selected, so its store and background handlers never coexist with
/// the rewrite engine.
@MainActor
final class LegacyEngine {
    let modelContainer: ModelContainer

    init() {
        do {
            modelContainer = try ModelContainer(for:
                ScanSessionEntity.self,
                PhotoPointEntity.self,
                DuplicateGroupEntity.self,
                GroupMemberEntity.self,
                SimilarityEdgeEntity.self
            )
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
        BackgroundScanService.register(modelContainer: modelContainer)
        ContinuousScanCoordinator.register()
    }
}

/// The legacy app root, unchanged apart from moving out of the `App` struct.
struct LegacyRootView: View {
    enum BootstrapStatus {
        case loading
        case onboarding(AppSettings)
        case ready(any DependencyProviding)
        case failed(AppError)
    }

    let engine: LegacyEngine
    @State private var bootstrapStatus: BootstrapStatus = .loading
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        contentView
            .environment(\.dependencies, activeDependencies)
            .task {
                await setup()
            }
            .onChange(of: scenePhase) { _, newPhase in
                handleScenePhase(newPhase)
            }
            .modelContainer(engine.modelContainer)
    }

    private var activeDependencies: (any DependencyProviding)? {
        switch bootstrapStatus {
        case .ready(let deps): deps
        default: nil
        }
    }

    @ViewBuilder
    private var contentView: some View {
        switch bootstrapStatus {
        case .loading:
            ProgressView(L10n.loading)

        case .onboarding(let settings):
            OnboardingView(settings: settings) {
                Task { await setupAfterOnboarding(settings: settings) }
            }

        case .ready:
            RootNavigationView()

        case .failed(let error):
            authorizationErrorView(error)
        }
    }

    private func authorizationErrorView(_ error: AppError) -> some View {
        VStack(spacing: QSpacing.md) {
            QStatusIcon(QIcons.photoError, size: QSize.iconLarge, color: QColors.error)
            Text(L10n.photoAccessRequired)
                .font(QTypography.titleMedium)
            Text(error.localizedDescription)
                .font(QTypography.bodyMedium)
                .foregroundStyle(QColors.textTertiary)
                .multilineTextAlignment(.center)

            Button(L10n.openSettings) {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            }
            .buttonStyle(.qPrimary)
        }
        .padding()
    }

    private func setup() async {
        let settings = AppSettings()

        guard settings.hasCompletedOnboarding else {
            bootstrapStatus = .onboarding(settings)
            return
        }

        await bootstrapDependencies(settings: settings)
    }

    private func setupAfterOnboarding(settings: AppSettings) async {
        await bootstrapDependencies(settings: settings)
    }

    private func bootstrapDependencies(settings: AppSettings) async {
        let photoLibrary = PhotoLibraryService()

        let currentAuth = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        switch currentAuth {
        case .authorized, .limited:
            break
        default:
            do {
                try await photoLibrary.requestAuthorization()
            } catch {
                bootstrapStatus = .failed(error)
                return
            }
        }

        do {
            bootstrapStatus = .ready(try await AppDependencies.shared(
                modelContainer: engine.modelContainer,
                settings: settings
            ))
        } catch {
            bootstrapStatus = .failed(error as? AppError ?? .unknown(error.localizedDescription))
        }
    }

    private func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .background:
            guard case .ready = bootstrapStatus else { return }
            // An active scan schedules its urgent fallback through the interactor.
            if !ContinuousScanCoordinator.hasActiveScan {
                BackgroundScanService.schedule()
            }
        case .active:
            break
        case .inactive:
            break
        @unknown default:
            break
        }
    }
}
