import Foundation

enum PhotoPointStatus: String, Sendable {
    case indexed
    case skipped
    case failed
    case deleted
    case pendingReindex

    var hasUsableVector: Bool {
        switch self {
        case .indexed, .skipped:
            true
        case .failed, .deleted, .pendingReindex:
            false
        }
    }
}

struct ScanPhotoRecord: Sendable {
    let assetLocalId: String
    let vectorUUID: String
    let status: PhotoPointStatus
    let embeddingDimensions: Int
    let pixelWidth: Int
    let pixelHeight: Int
    let creationDate: Date?
    let lastError: String?
}

struct SimilarityEdgeRecord: Sendable {
    let sourceVectorUUID: String
    let targetVectorUUID: String
    let score: Float

    var normalizedSource: String {
        min(sourceVectorUUID, targetVectorUUID)
    }

    var normalizedTarget: String {
        max(sourceVectorUUID, targetVectorUUID)
    }

    func pairKey(sessionId: UUID) -> String {
        "\(sessionId.uuidString.lowercased()):\(normalizedSource)|\(normalizedTarget)"
    }
}

struct PersistScanBatchResult: Sendable {
    let groups: [DuplicateGroup]
}
