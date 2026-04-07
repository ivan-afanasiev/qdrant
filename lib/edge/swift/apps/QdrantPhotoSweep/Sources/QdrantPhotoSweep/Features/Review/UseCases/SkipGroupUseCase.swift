import Foundation

struct SkipGroupInput: Sendable {
    let group: DuplicateGroup
}

struct SkipGroupUseCase: UseCase {
    let scanStore: any ScanSessionStoring

    func execute(_ input: SkipGroupInput) async throws -> Void {
        guard let groupUUID = UUID(uuidString: input.group.id) else { return }
        let allIds = Set(input.group.photos.map(\.id))
        try await scanStore.markGroupReviewed(
            groupId: groupUUID,
            keptVectorUUIDs: allIds
        )
    }
}
