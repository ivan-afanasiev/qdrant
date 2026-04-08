import Foundation
import SwiftData

@Model
final class DuplicateGroupEntity {
    @Attribute(.unique) var id: UUID
    var status: String
    var detectedAt: Date
    var componentKey: String
    var lastError: String?

    var session: ScanSessionEntity?

    @Relationship(deleteRule: .cascade, inverse: \GroupMemberEntity.group)
    var members: [GroupMemberEntity] = []

    init(
        id: UUID = UUID(),
        status: String = DuplicateGroupStatus.pending.rawValue,
        detectedAt: Date = .now,
        componentKey: String = "",
        lastError: String? = nil,
        session: ScanSessionEntity? = nil
    ) {
        self.id = id
        self.status = status
        self.detectedAt = detectedAt
        self.componentKey = componentKey
        self.lastError = lastError
        self.session = session
    }
}

enum DuplicateGroupStatus: String {
    case pending
    case deleting
    case reviewed
    case deleted
}
