import SwiftUI

struct Dependencies {
    let vectorStore: any VectorStoring
    let embeddingService: any EmbeddingProviding
    let photoLibrary: any PhotoLibraryProviding
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
