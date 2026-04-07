import Foundation

struct LoadNextGroupOutput: Sendable {
    let group: DuplicateGroup?
    let pendingCount: Int
}

struct LoadNextGroupUseCase: UseCase {
    let scanStore: any ScanSessionStoring

    func execute(_ input: Void) async throws -> LoadNextGroupOutput {
        let count = try await scanStore.pendingGroupCount()
        let dto = try await scanStore.loadNextPendingGroup()
        let group = dto?.toDuplicateGroup()
        return LoadNextGroupOutput(group: group, pendingCount: count)
    }
}
