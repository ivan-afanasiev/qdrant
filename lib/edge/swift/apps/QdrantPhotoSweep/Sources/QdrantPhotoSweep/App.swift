import SwiftData
import SwiftUI
import Photos

@main
struct QdrantPhotoSweepApp: App {
    enum BootstrapStatus {
        case loading
        case onboarding(AppSettings)
        case ready(Dependencies)
        case failed(AppError)
    }

    @State private var bootstrapStatus: BootstrapStatus = .loading
    @Environment(\.scenePhase) private var scenePhase

    let modelContainer: ModelContainer

    init() {
        do {
            modelContainer = try ModelContainer(for:
                ScanSessionEntity.self,
                PhotoPointEntity.self,
                DuplicateGroupEntity.self,
                GroupMemberEntity.self
            )
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
        BackgroundScanService.register(modelContainer: modelContainer)
        ContinuousScanCoordinator.register()
    }

    var body: some Scene {
        WindowGroup {
            contentView
                .environment(\.dependencies, activeDependencies)
                .task {
                    await setup()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    handleScenePhase(newPhase)
                }
        }
        .modelContainer(modelContainer)
    }

    private var activeDependencies: Dependencies? {
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

        let embeddingService = VisionEmbeddingService()

        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let shardDir = documentsPath.appendingPathComponent("qdrant-edge")

        let vectorStore = QdrantVectorStore(
            path: shardDir.path,
            dimensions: 0
        )
        await vectorStore.restoreDimensionsFromDisk()

        let scanStore = SwiftDataScanStore(modelContainer: modelContainer)

        bootstrapStatus = .ready(Dependencies(
            vectorStore: vectorStore,
            embeddingService: embeddingService,
            photoLibrary: photoLibrary,
            scanStore: scanStore,
            settings: settings
        ))
    }

    private func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .background:
            guard case .ready = bootstrapStatus else { return }
            BackgroundScanService.schedule()
        case .active:
            break
        case .inactive:
            break
        @unknown default:
            break
        }
    }
}
