import Foundation

public struct VectorPoint: Sendable {
    public let id: String
    public let vector: [Float]
    public let payloadJson: String
    public init(id: String, vector: [Float], payloadJson: String) {
        self.id = id
        self.vector = vector
        self.payloadJson = payloadJson
    }
}

public struct ScoredResult: Sendable, Identifiable {
    public let id: String
    public let score: Float
    public let payloadJson: String?
    public let vectorJson: String?
    public init(id: String, score: Float, payloadJson: String?, vectorJson: String?) {
        self.id = id
        self.score = score
        self.payloadJson = payloadJson
        self.vectorJson = vectorJson
    }
}

public struct ScrollPage: Sendable {
    public let records: [VectorRecord]
    public let nextOffset: String?
    public init(records: [VectorRecord], nextOffset: String?) {
        self.records = records
        self.nextOffset = nextOffset
    }
}

public struct VectorRecord: Sendable, Identifiable {
    public let id: String
    public let payloadJson: String?
    public let vectorJson: String?
    public init(id: String, payloadJson: String?, vectorJson: String?) {
        self.id = id
        self.payloadJson = payloadJson
        self.vectorJson = vectorJson
    }
}

/// Restricts neighborhood search to points whose payload creation time is in range.
/// Points without a creation time never match a range.
public struct VectorSearchFilter: Equatable, Sendable {
    public let creationRange: ClosedRange<Double>

    public init(creationRange: ClosedRange<Double>) {
        self.creationRange = creationRange
    }

    public init(scope: DateRange) {
        creationRange = scope.start.timeIntervalSince1970...scope.end.timeIntervalSince1970
    }
}

/// Payload stored with every vector: the asset and its creation time (seconds since 1970).
public struct VectorPayload: Codable, Equatable, Sendable {
    public static let creationKey = "created"

    public let asset: String
    public let created: Double?

    public init(asset: AssetID, creationDate: Date?) {
        self.asset = asset.rawValue
        self.created = creationDate?.timeIntervalSince1970
    }

    public var assetID: AssetID { AssetID(asset) }
    public var creationDate: Date? { created.map(Date.init(timeIntervalSince1970:)) }

    public var json: String {
        guard let data = try? JSONEncoder().encode(self), let json = String(data: data, encoding: .utf8) else { return "{}" }
        return json
    }

    public static func decode(_ json: String?) -> VectorPayload? {
        guard let data = json?.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(VectorPayload.self, from: data)
    }
}

public protocol VectorStoring: Sendable {
    func exists(id: String) async throws(AdapterError) -> Bool
    func upsert(points: [VectorPoint]) async throws(AdapterError)
    func search(vector: [Float], limit: Int, threshold: Float) async throws(AdapterError) -> [ScoredResult]
    /// One page of matches scoring at least `threshold`, best first, using exact search so
    /// consecutive pages neither skip nor repeat points. A page shorter than `limit` is the last.
    func searchPage(
        vector: [Float],
        threshold: Float,
        filter: VectorSearchFilter?,
        offset: Int,
        limit: Int
    ) async throws(AdapterError) -> [ScoredResult]
    /// The stored vector of a point, or nil if the point does not exist.
    func vector(id: String) async throws(AdapterError) -> [Float]?
    func scroll(offset: String?, limit: Int) async throws(AdapterError) -> ScrollPage
    func delete(ids: [String]) async throws(AdapterError)
    func count() async throws(AdapterError) -> Int
    func close() async
}
