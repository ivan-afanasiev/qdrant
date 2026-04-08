import SwiftData
import SwiftUI

// MARK: - DependencyProviding Protocol

protocol DependencyProviding {
    var vectorStore: any VectorStoring { get }
    var embeddingService: any EmbeddingProviding { get }
    var photoLibrary: any PhotoLibraryProviding { get }
    var scanStore: any ScanSessionStoring { get }
    var settings: AppSettings { get }
}

// MARK: - Live Implementation

final class AppDependencies: DependencyProviding {
    let vectorStore: any VectorStoring
    let embeddingService: any EmbeddingProviding
    let photoLibrary: any PhotoLibraryProviding
    let scanStore: any ScanSessionStoring
    let settings: AppSettings

    init(
        vectorStore: any VectorStoring,
        embeddingService: any EmbeddingProviding,
        photoLibrary: any PhotoLibraryProviding,
        scanStore: any ScanSessionStoring,
        settings: AppSettings
    ) {
        self.vectorStore = vectorStore
        self.embeddingService = embeddingService
        self.photoLibrary = photoLibrary
        self.scanStore = scanStore
        self.settings = settings
    }

    @MainActor
    static func forBackground(modelContainer: ModelContainer) async -> AppDependencies {
        let photoLibrary = PhotoLibraryService()
        let embeddingService = VisionEmbeddingService()

        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let shardDir = documentsPath.appendingPathComponent("qdrant-edge")
        let vectorStore = QdrantVectorStore(path: shardDir.path, dimensions: 0)
        await vectorStore.restoreDimensionsFromDisk()

        let scanStore = SwiftDataScanStore(modelContainer: modelContainer)
        let settings = AppSettings()

        return AppDependencies(
            vectorStore: vectorStore,
            embeddingService: embeddingService,
            photoLibrary: photoLibrary,
            scanStore: scanStore,
            settings: settings
        )
    }
}

// MARK: - SwiftUI Environment

private struct DependencyContainerKey: EnvironmentKey {
    static let defaultValue: (any DependencyProviding)? = nil
}

extension EnvironmentValues {
    var dependencies: (any DependencyProviding)? {
        get { self[DependencyContainerKey.self] }
        set { self[DependencyContainerKey.self] = newValue }
    }
}
