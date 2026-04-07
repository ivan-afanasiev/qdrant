import Foundation

struct GroupsPageInput: Sendable {
    let offset: Int
    let limit: Int
}

struct GroupSummary: Identifiable, Hashable, Sendable {
    let id: UUID
    let photoCount: Int
    let representativeAssetId: String
    let representativePixelWidth: Int
    let representativePixelHeight: Int
    let detectedAt: Date
}

struct GroupsPageOutput: Sendable {
    let groups: [GroupSummary]
    let totalCount: Int
    let hasMore: Bool
}

struct LoadGroupsPageUseCase: UseCase {
    let scanStore: any ScanSessionStoring

    func execute(_ input: GroupsPageInput) async throws -> GroupsPageOutput {
        let totalCount = try await scanStore.pendingGroupCount()
        let dtos = try await scanStore.loadPendingGroupsPage(offset: input.offset, limit: input.limit)

        let groups = dtos.compactMap { dto -> GroupSummary? in
            guard let representative = dto.members
                .max(by: { $0.pixelWidth * $0.pixelHeight < $1.pixelWidth * $1.pixelHeight })
            else { return nil }

            return GroupSummary(
                id: dto.id,
                photoCount: dto.members.count,
                representativeAssetId: representative.assetLocalId,
                representativePixelWidth: representative.pixelWidth,
                representativePixelHeight: representative.pixelHeight,
                detectedAt: dto.detectedAt
            )
        }

        let hasMore = input.offset + dtos.count < totalCount
        return GroupsPageOutput(groups: groups, totalCount: totalCount, hasMore: hasMore)
    }
}
