import Foundation
import SwiftData

@Model
final class SimilarityEdgeEntity {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var pairKey: String
    var sourceVectorUUID: String
    var targetVectorUUID: String
    var score: Float

    var session: ScanSessionEntity?

    init(
        id: UUID = UUID(),
        pairKey: String,
        sourceVectorUUID: String,
        targetVectorUUID: String,
        score: Float,
        session: ScanSessionEntity? = nil
    ) {
        self.id = id
        self.pairKey = pairKey
        self.sourceVectorUUID = sourceVectorUUID
        self.targetVectorUUID = targetVectorUUID
        self.score = score
        self.session = session
    }
}
