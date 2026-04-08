import Foundation

struct ClearDatabaseUseCase: UseCase {
    let vectorStore: any VectorStoring
    let scanStore: any ScanSessionStoring

    func execute(_ input: Void) async throws -> Void {
        try await scanStore.resetAllData()
        try await vectorStore.reset()
    }
}
