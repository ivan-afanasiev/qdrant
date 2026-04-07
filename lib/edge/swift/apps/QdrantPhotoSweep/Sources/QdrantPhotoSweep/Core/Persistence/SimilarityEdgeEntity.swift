import Foundation
import SwiftData

@Model
final class SimilarityEdgeEntity {
    @Attribute(.unique) var id: UUID
    var sourceVectorUUID: String
    var targetVectorUUID: String
    var score: Float

    var session: ScanSessionEntity?

    init(
        id: UUID = UUID(),
        sourceVectorUUID: String,
        targetVectorUUID: String,
        score: Float,
        session: ScanSessionEntity? = nil
    ) {
        self.id = id
        self.sourceVectorUUID = sourceVectorUUID
        self.targetVectorUUID = targetVectorUUID
        self.score = score
        self.session = session
    }
}
