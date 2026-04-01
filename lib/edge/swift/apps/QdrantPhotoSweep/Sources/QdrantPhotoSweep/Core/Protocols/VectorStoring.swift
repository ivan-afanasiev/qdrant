import Foundation

struct VectorPoint: Sendable {
    let id: String
    let vector: [Float]
    let payloadJson: String
}

struct ScoredResult: Sendable, Identifiable {
    let id: String
    let score: Float
    let payloadJson: String?
    let vectorJson: String?
}

struct ScrollPage: Sendable {
    let records: [VectorRecord]
    let nextOffset: String?
}

struct VectorRecord: Sendable, Identifiable {
    let id: String
    let payloadJson: String?
    let vectorJson: String?
}

protocol VectorStoring: Sendable {
    func updateDimensions(_ dims: Int) async
    func upsert(points: [VectorPoint]) async throws(AppError)
    func search(vector: [Float], limit: Int, threshold: Float) async throws(AppError) -> [ScoredResult]
    func scroll(offset: String?, limit: Int) async throws(AppError) -> ScrollPage
    func delete(ids: [String]) async throws(AppError)
    func count() async throws(AppError) -> Int
    func close() async
}
