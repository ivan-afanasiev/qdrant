import SwiftUI

@main
struct QdrantPhotoSweepApp: App {
    @State private var dependencies: Dependencies?
    @Environment(\.scenePhase) private var scenePhase
    @State private var authorizationError: AppError?

    var body: some Scene {
        WindowGroup {
            contentView
                .environment(\.dependencies, dependencies)
                .task {
                    await setup()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    handleScenePhase(newPhase)
                }
        }
    }

    @ViewBuilder
    private var contentView: some View {
        switch (dependencies, authorizationError) {
        case (.some, _):
            RootNavigationView()

        case (_, .some(let error)):
            authorizationErrorView(error)

        case (.none, .none):
            ProgressView(L10n.loading)
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
        let photoLibrary = PhotoLibraryService()
        do {
            try await photoLibrary.requestAuthorization()
        } catch {
            authorizationError = error
            return
        }

        let embeddingService = VisionEmbeddingService()

        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let shardDir = documentsPath.appendingPathComponent("qdrant-edge")

        let vectorStore = QdrantVectorStore(
            path: shardDir.path,
            dimensions: 0
        )

        dependencies = Dependencies(
            vectorStore: vectorStore,
            embeddingService: embeddingService,
            photoLibrary: photoLibrary
        )
    }

    private func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .background:
            guard let store = dependencies?.vectorStore else { return }
            Task { await store.close() }
        case .active, .inactive:
            break
        @unknown default:
            break
        }
    }
}
