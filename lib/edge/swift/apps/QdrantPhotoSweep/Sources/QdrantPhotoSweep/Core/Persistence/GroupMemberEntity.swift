import Foundation
import SwiftData

@Model
final class GroupMemberEntity {
    var assetLocalId: String
    var vectorUUID: String
    var score: Float
    var pixelWidth: Int
    var pixelHeight: Int
    var creationDate: Date?
    var isKept: Bool?

    var group: DuplicateGroupEntity?

    init(
        assetLocalId: String,
        vectorUUID: String,
        score: Float,
        pixelWidth: Int,
        pixelHeight: Int,
        creationDate: Date? = nil,
        isKept: Bool? = nil,
        group: DuplicateGroupEntity? = nil
    ) {
        self.assetLocalId = assetLocalId
        self.vectorUUID = vectorUUID
        self.score = score
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.creationDate = creationDate
        self.isKept = isKept
        self.group = group
    }
}
