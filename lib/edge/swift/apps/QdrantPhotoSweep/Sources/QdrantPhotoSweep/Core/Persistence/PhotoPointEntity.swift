import Foundation
import SwiftData

@Model
final class PhotoPointEntity {
    @Attribute(.unique) var assetLocalId: String
    var vectorUUID: String
    var embeddingDimensions: Int
    var indexedAt: Date

    var session: ScanSessionEntity?

    init(
        assetLocalId: String,
        vectorUUID: String,
        embeddingDimensions: Int,
        indexedAt: Date = .now,
        session: ScanSessionEntity? = nil
    ) {
        self.assetLocalId = assetLocalId
        self.vectorUUID = vectorUUID
        self.embeddingDimensions = embeddingDimensions
        self.indexedAt = indexedAt
        self.session = session
    }
}
