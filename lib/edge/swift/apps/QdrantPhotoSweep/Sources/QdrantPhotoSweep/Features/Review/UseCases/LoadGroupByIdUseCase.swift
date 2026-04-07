import Foundation

struct LoadGroupByIdUseCase: UseCase {
    let scanStore: any ScanSessionStoring

    func execute(_ input: UUID) async throws -> DuplicateGroup? {
        let dto = try await scanStore.loadPendingGroup(id: input)
        return dto?.toDuplicateGroup()
    }
}
