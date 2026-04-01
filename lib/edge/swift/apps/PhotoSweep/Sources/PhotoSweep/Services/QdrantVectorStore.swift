import Foundation
import QdrantEdge

actor QdrantVectorStore: VectorStoring {
    private let path: String
    private let dimensions: Int
    private var shard: EdgeShard?

    init(path: String, dimensions: Int) {
        self.path = path
        self.dimensions = dimensions
    }

    private func ensureShard() throws(AppError) -> EdgeShard {
        if let existing = shard {
            return existing
        }
        do {
            let config = EdgeConfig(
                vectorData: [
                    "": VectorDataConfig(
                        size: UInt64(dimensions),
                        distance: .cosine,
                        quantizationConfig: nil,
                        multivectorConfig: nil,
                        datatype: nil
                    )
                ],
                sparseVectorData: [:]
            )
            let loaded = try EdgeShard.load(path: path, config: config)
            shard = loaded
            return loaded
        } catch {
            throw .vectorStore("Failed to load shard: \(error.localizedDescription)")
        }
    }

    nonisolated func upsert(points: [VectorPoint]) async throws(AppError) {
        try await _upsert(points: points)
    }

    private func _upsert(points: [VectorPoint]) throws(AppError) {
        let shard = try ensureShard()
        let edgePoints = points.map { point in
            Point(
                id: .uuid(value: point.id),
                vector: .single(values: point.vector),
                payload: point.payloadJson
            )
        }
        do {
            let operation = try UpdateOperation.upsertPoints(points: edgePoints)
            try shard.update(operation: operation)
        } catch {
            throw .vectorStore("Upsert failed: \(error.localizedDescription)")
        }
    }

    nonisolated func search(vector: [Float], limit: Int, threshold: Float) async throws(AppError) -> [ScoredResult] {
        try await _search(vector: vector, limit: limit, threshold: threshold)
    }

    private func _search(vector: [Float], limit: Int, threshold: Float) throws(AppError) -> [ScoredResult] {
        let shard = try ensureShard()
        do {
            let request = SearchRequest(
                query: .nearest(vector: vector, using: nil),
                limit: UInt64(limit),
                offset: nil,
                filter: nil,
                params: nil,
                withVector: .bool(enable: false),
                withPayload: .bool(enable: true),
                scoreThreshold: threshold
            )
            let results = try shard.search(request: request)
            return results.map { scored in
                ScoredResult(
                    id: pointIdString(scored.id),
                    score: scored.score,
                    payloadJson: scored.payload,
                    vectorJson: scored.vector
                )
            }
        } catch {
            throw .vectorStore("Search failed: \(error.localizedDescription)")
        }
    }

    nonisolated func scroll(offset: String?, limit: Int) async throws(AppError) -> ScrollPage {
        try await _scroll(offset: offset, limit: limit)
    }

    private func _scroll(offset: String?, limit: Int) throws(AppError) -> ScrollPage {
        let shard = try ensureShard()
        let pointOffset: PointId? = offset.map { .uuid(value: $0) }
        do {
            let request = ScrollRequest(
                offset: pointOffset,
                limit: UInt64(limit),
                filter: nil,
                withPayload: .bool(enable: true),
                withVector: .bool(enable: true),
                orderBy: nil
            )
            let response = try shard.scroll(request: request)
            let records = response.records.map { record in
                VectorRecord(
                    id: pointIdString(record.id),
                    payloadJson: record.payload,
                    vectorJson: record.vector
                )
            }
            let next = response.nextOffset.map(pointIdString)
            return ScrollPage(records: records, nextOffset: next)
        } catch {
            throw .vectorStore("Scroll failed: \(error.localizedDescription)")
        }
    }

    nonisolated func delete(ids: [String]) async throws(AppError) {
        try await _delete(ids: ids)
    }

    private func _delete(ids: [String]) throws(AppError) {
        let shard = try ensureShard()
        let pointIds = ids.map { PointId.uuid(value: $0) }
        do {
            let operation = UpdateOperation.deletePoints(pointIds: pointIds)
            try shard.update(operation: operation)
        } catch {
            throw .vectorStore("Delete failed: \(error.localizedDescription)")
        }
    }

    nonisolated func count() async throws(AppError) -> Int {
        try await _count()
    }

    private func _count() throws(AppError) -> Int {
        let shard = try ensureShard()
        do {
            let result = try shard.count(request: CountRequest(filter: nil, exact: true))
            return Int(result)
        } catch {
            throw .vectorStore("Count failed: \(error.localizedDescription)")
        }
    }

    nonisolated func close() async {
        await _close()
    }

    private func _close() {
        shard?.close()
        shard = nil
    }

    private func pointIdString(_ id: PointId) -> String {
        switch id {
        case .numId(let value): String(value)
        case .uuid(let value): value
        }
    }
}
