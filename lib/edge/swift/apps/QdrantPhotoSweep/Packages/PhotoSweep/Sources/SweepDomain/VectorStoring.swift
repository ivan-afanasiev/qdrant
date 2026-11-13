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

public protocol VectorStoring: Sendable {
    func exists(id: String) async throws(AdapterError) -> Bool
    func upsert(points: [VectorPoint]) async throws(AdapterError)
    func search(vector: [Float], limit: Int, threshold: Float) async throws(AdapterError) -> [ScoredResult]
    func scroll(offset: String?, limit: Int) async throws(AdapterError) -> ScrollPage
    func delete(ids: [String]) async throws(AdapterError)
    func count() async throws(AdapterError) -> Int
    func close() async
}
