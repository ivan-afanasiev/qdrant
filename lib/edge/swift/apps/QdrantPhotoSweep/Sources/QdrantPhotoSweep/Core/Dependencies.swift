import SwiftUI

@Observable
final class AppSettings {
    static let defaultSimilarityThreshold: Float = 0.92
    var similarityThreshold: Float = AppSettings.defaultSimilarityThreshold
}

struct Dependencies {
    let vectorStore: any VectorStoring
    let embeddingService: any EmbeddingProviding
    let photoLibrary: any PhotoLibraryProviding
    let settings: AppSettings
}

private struct DependenciesKey: EnvironmentKey {
    static let defaultValue: Dependencies? = nil
}

extension EnvironmentValues {
    var dependencies: Dependencies? {
        get { self[DependenciesKey.self] }
        set { self[DependenciesKey.self] = newValue }
    }
}
