import SwiftUI

@main
struct PhotoSweepApp: App {
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
            ProgressView("Loading...")
        }
    }

    private func authorizationErrorView(_ error: AppError) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.badge.exclamationmark")
                .font(.system(size: 48))
                .foregroundStyle(.red)
            Text("Photo Access Required")
                .font(.title2.bold())
            Text(error.localizedDescription)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Open Settings") {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            }
            .buttonStyle(.borderedProminent)
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

        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let shardPath = documentsPath.appendingPathComponent("qdrant-edge").path

        let embeddingService = VisionEmbeddingService()
        let vectorStore = QdrantVectorStore(
            path: shardPath,
            dimensions: embeddingService.dimensions
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
