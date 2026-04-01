import Foundation

struct PhotoReference: Identifiable, Hashable, Sendable {
    let id: String
    let assetId: String
    let creationDate: Date?
    let pixelWidth: Int
    let pixelHeight: Int
    let score: Float

    var megapixels: Double {
        Double(pixelWidth * pixelHeight) / 1_000_000
    }

    var resolution: String {
        "\(pixelWidth) × \(pixelHeight)"
    }
}

struct DuplicateGroup: Identifiable, Hashable, Sendable {
    let id: String
    let photos: [PhotoReference]
    let bestCandidate: PhotoReference

    var count: Int { photos.count }
}

extension DuplicateGroup {
    static func from(
        photoIds: [String],
        payloads: [String: String?],
        scores: [String: Float]
    ) -> DuplicateGroup? {
        guard photoIds.count > 1 else { return nil }

        let photos: [PhotoReference] = photoIds.compactMap { pid in
            guard let payloadJson = payloads[pid] ?? nil else {
                return PhotoReference(
                    id: pid,
                    assetId: pid,
                    creationDate: nil,
                    pixelWidth: 0,
                    pixelHeight: 0,
                    score: scores[pid, default: 0]
                )
            }
            return parsePhotoReference(id: pid, json: payloadJson, score: scores[pid, default: 0])
        }

        guard photos.count > 1 else { return nil }

        let best = photos.max(by: { $0.megapixels < $1.megapixels }) ?? photos[0]
        return DuplicateGroup(
            id: UUID().uuidString,
            photos: photos.sorted(by: { $0.megapixels > $1.megapixels }),
            bestCandidate: best
        )
    }
}

private func parsePhotoReference(id: String, json: String, score: Float) -> PhotoReference {
    guard let data = json.data(using: .utf8),
          let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return PhotoReference(
            id: id, assetId: id, creationDate: nil,
            pixelWidth: 0, pixelHeight: 0, score: score
        )
    }

    let assetId = (dict["assetId"] as? String) ?? id
    let dateString = dict["creationDate"] as? String
    let creationDate = dateString.flatMap { ISO8601DateFormatter().date(from: $0) }
    let pixelWidth = (dict["pixelWidth"] as? Int) ?? 0
    let pixelHeight = (dict["pixelHeight"] as? Int) ?? 0

    return PhotoReference(
        id: id,
        assetId: assetId,
        creationDate: creationDate,
        pixelWidth: pixelWidth,
        pixelHeight: pixelHeight,
        score: score
    )
}
