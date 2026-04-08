import Foundation

struct DeleteGroupInput: Sendable {
    let group: DuplicateGroup
    let keptIds: Set<String>
}

struct DeleteGroupOutput: Sendable {
    let deleted: Int
    let kept: Int
}

struct DeleteGroupUseCase: UseCase {
    let photoLibrary: any PhotoLibraryProviding
    let vectorStore: any VectorStoring
    let scanStore: any ScanSessionStoring

    func execute(_ input: DeleteGroupInput) async throws -> DeleteGroupOutput {
        let kept = input.keptIds
        let idsToDelete = input.group.photos
            .filter { !kept.contains($0.id) }
            .map(\.assetId)

        guard let groupUUID = UUID(uuidString: input.group.id) else {
            return DeleteGroupOutput(deleted: 0, kept: kept.count)
        }

        guard !idsToDelete.isEmpty else {
            try await scanStore.markGroupReviewed(
                groupId: groupUUID,
                keptVectorUUIDs: kept
            )
            return DeleteGroupOutput(deleted: 0, kept: kept.count)
        }

        let vectorUUIDs = idsToDelete.map { deterministicUUID(from: $0) }
        let deletedVectorUUIDs = Set(vectorUUIDs)
        try await scanStore.markGroupDeletionPending(
            groupId: groupUUID,
            keptVectorUUIDs: kept,
            deletedVectorUUIDs: deletedVectorUUIDs
        )

        do {
            try await vectorStore.delete(ids: vectorUUIDs)
            try await photoLibrary.deleteAssets(idsToDelete)
        } catch {
            let appError = error as? AppError ?? .unknown(error.localizedDescription)
            try? await scanStore.markGroupDeletionFailed(
                groupId: groupUUID,
                reason: appError.localizedDescription,
                deletedVectorUUIDs: deletedVectorUUIDs
            )
            throw appError
        }

        try await scanStore.markGroupDeleted(
            groupId: groupUUID,
            keptVectorUUIDs: kept,
            deletedVectorUUIDs: deletedVectorUUIDs
        )

        return DeleteGroupOutput(deleted: idsToDelete.count, kept: kept.count)
    }
}
