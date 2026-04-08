import Foundation
import SwiftData

@Model
final class ScanSessionEntity {
    @Attribute(.unique) var id: UUID
    var rangeStart: Date
    var rangeEnd: Date
    var scannedAt: Date
    var status: String
    var totalPhotos: Int
    var indexedPhotos: Int
    var skippedPhotos: Int
    var failedPhotos: Int
    var leaseOwner: String?
    var leaseExpiresAt: Date?

    @Relationship(deleteRule: .cascade, inverse: \PhotoPointEntity.session)
    var photoPoints: [PhotoPointEntity] = []

    @Relationship(deleteRule: .cascade, inverse: \DuplicateGroupEntity.session)
    var duplicateGroups: [DuplicateGroupEntity] = []

    @Relationship(deleteRule: .cascade, inverse: \SimilarityEdgeEntity.session)
    var similarityEdges: [SimilarityEdgeEntity] = []

    init(
        id: UUID = UUID(),
        rangeStart: Date,
        rangeEnd: Date,
        scannedAt: Date = .now,
        status: String = ScanSessionStatus.scanning.rawValue,
        totalPhotos: Int = 0,
        indexedPhotos: Int = 0,
        skippedPhotos: Int = 0,
        failedPhotos: Int = 0,
        leaseOwner: String? = nil,
        leaseExpiresAt: Date? = nil
    ) {
        self.id = id
        self.rangeStart = rangeStart
        self.rangeEnd = rangeEnd
        self.scannedAt = scannedAt
        self.status = status
        self.totalPhotos = totalPhotos
        self.indexedPhotos = indexedPhotos
        self.skippedPhotos = skippedPhotos
        self.failedPhotos = failedPhotos
        self.leaseOwner = leaseOwner
        self.leaseExpiresAt = leaseExpiresAt
    }
}

enum ScanSessionStatus: String {
    case scanning
    case completed
    case interrupted
    case failed
}
