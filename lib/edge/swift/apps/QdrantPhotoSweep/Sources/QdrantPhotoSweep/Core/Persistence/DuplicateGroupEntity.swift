import Foundation
import SwiftData

@Model
final class DuplicateGroupEntity {
    @Attribute(.unique) var id: UUID
    var status: String
    var detectedAt: Date

    var session: ScanSessionEntity?

    @Relationship(deleteRule: .cascade, inverse: \GroupMemberEntity.group)
    var members: [GroupMemberEntity] = []

    init(
        id: UUID = UUID(),
        status: String = DuplicateGroupStatus.pending.rawValue,
        detectedAt: Date = .now,
        session: ScanSessionEntity? = nil
    ) {
        self.id = id
        self.status = status
        self.detectedAt = detectedAt
        self.session = session
    }
}

enum DuplicateGroupStatus: String {
    case pending
    case reviewed
    case deleted
}
