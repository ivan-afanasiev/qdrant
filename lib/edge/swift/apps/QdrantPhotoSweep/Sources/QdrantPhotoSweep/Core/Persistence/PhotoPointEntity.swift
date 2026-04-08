import Foundation
import SwiftData

@Model
final class PhotoPointEntity {
    @Attribute(.unique) var assetLocalId: String
    var vectorUUID: String
    var embeddingDimensions: Int
    var indexedAt: Date
    var status: String
    var lastError: String?
    var pixelWidth: Int
    var pixelHeight: Int
    var creationDate: Date?

    var session: ScanSessionEntity?

    init(
        assetLocalId: String,
        vectorUUID: String,
        embeddingDimensions: Int,
        indexedAt: Date = .now,
        status: String = PhotoPointStatus.indexed.rawValue,
        lastError: String? = nil,
        pixelWidth: Int = 0,
        pixelHeight: Int = 0,
        creationDate: Date? = nil,
        session: ScanSessionEntity? = nil
    ) {
        self.assetLocalId = assetLocalId
        self.vectorUUID = vectorUUID
        self.embeddingDimensions = embeddingDimensions
        self.indexedAt = indexedAt
        self.status = status
        self.lastError = lastError
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.creationDate = creationDate
        self.session = session
    }
}
