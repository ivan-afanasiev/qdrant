import Foundation
import SwiftData

struct DuplicateGroupDTO: Identifiable, Sendable {
    let id: UUID
    let status: DuplicateGroupStatus
    let detectedAt: Date
    let members: [GroupMemberDTO]
}

struct GroupMemberDTO: Identifiable, Sendable {
    let assetLocalId: String
    let vectorUUID: String
    let score: Float
    let pixelWidth: Int
    let pixelHeight: Int
    let creationDate: Date?
    let isKept: Bool?

    var id: String { vectorUUID }
}

extension DuplicateGroupEntity {
    func toDTO() -> DuplicateGroupDTO {
        DuplicateGroupDTO(
            id: id,
            status: DuplicateGroupStatus(rawValue: status) ?? .pending,
            detectedAt: detectedAt,
            members: members.map { $0.toDTO() }
        )
    }
}

extension GroupMemberEntity {
    func toDTO() -> GroupMemberDTO {
        GroupMemberDTO(
            assetLocalId: assetLocalId,
            vectorUUID: vectorUUID,
            score: score,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            creationDate: creationDate,
            isKept: isKept
        )
    }
}

extension DuplicateGroupDTO {
    func toDuplicateGroup() -> DuplicateGroup? {
        let photos: [PhotoReference] = members.map { member in
            PhotoReference(
                id: member.vectorUUID,
                assetId: member.assetLocalId,
                creationDate: member.creationDate,
                pixelWidth: member.pixelWidth,
                pixelHeight: member.pixelHeight,
                score: member.score
            )
        }
        guard photos.count > 1 else { return nil }

        let best = photos.max(by: { $0.megapixels < $1.megapixels }) ?? photos[0]
        return DuplicateGroup(
            id: id.uuidString,
            photos: photos.sorted(by: { $0.megapixels > $1.megapixels }),
            bestCandidate: best
        )
    }
}
