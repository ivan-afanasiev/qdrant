import Foundation

struct LoadDatabaseInfoOutput: Sendable {
    let pointCount: Int
}

struct LoadDatabaseInfoUseCase: UseCase {
    let vectorStore: any VectorStoring

    func execute(_ input: Void) async throws -> LoadDatabaseInfoOutput {
        let count = try await vectorStore.count()
        return LoadDatabaseInfoOutput(pointCount: count)
    }
}
