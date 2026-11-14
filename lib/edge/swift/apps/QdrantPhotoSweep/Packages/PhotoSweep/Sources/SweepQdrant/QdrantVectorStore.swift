import SweepDomain
import Foundation
import QdrantEdge

public actor QdrantVectorStore: VectorStoring {
    private let basePath: String
    private let dimensions: Int
    private var shard: EdgeShard?

    public init(path: String, dimensions: Int) {
        self.basePath = path
        self.dimensions = dimensions
    }

    private func ensureShard() throws(AdapterError) -> EdgeShard {
        if let existing = shard {
            return existing
        }
        guard dimensions > 0 else {
            throw .vectorStore("Vector dimensions not yet determined")
        }
        do {
            try FileManager.default.createDirectory(
                atPath: basePath,
                withIntermediateDirectories: true
            )
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
            let loaded = try EdgeShard.load(path: basePath, config: config)
            shard = loaded
            return loaded
        } catch let error as AdapterError {
            throw error
        } catch {
            throw .vectorStore("Failed to load shard: \(error.localizedDescription)")
        }
    }

    public nonisolated func exists(id: String) async throws(AdapterError) -> Bool {
        try await _exists(id: id)
    }

    private func _exists(id: String) throws(AdapterError) -> Bool {
        guard dimensions > 0 else { return false }
        let shard = try ensureShard()
        do {
            let request = ScrollRequest(
                offset: .uuid(value: id),
                limit: 1,
                filter: nil,
                withPayload: .bool(enable: false),
                withVector: .bool(enable: false),
                orderBy: nil
            )
            let response = try shard.scroll(request: request)
            return response.records.contains { pointIdString($0.id) == id }
        } catch {
            throw .vectorStore("Exists check failed: \(error.localizedDescription)")
        }
    }

    public nonisolated func upsert(points: [VectorPoint]) async throws(AdapterError) {
        try await _upsert(points: points)
    }

    private func _upsert(points: [VectorPoint]) throws(AdapterError) {
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

    public nonisolated func search(vector: [Float], limit: Int, threshold: Float) async throws(AdapterError) -> [ScoredResult] {
        try await _search(vector: vector, limit: limit, threshold: threshold)
    }

    private func _search(vector: [Float], limit: Int, threshold: Float) throws(AdapterError) -> [ScoredResult] {
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
                scoreThreshold: Self.inclusiveThreshold(threshold)
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

    public nonisolated func searchPage(
        vector: [Float],
        threshold: Float,
        filter: VectorSearchFilter?,
        offset: Int,
        limit: Int
    ) async throws(AdapterError) -> [ScoredResult] {
        try await _searchPage(vector: vector, threshold: threshold, filter: filter, offset: offset, limit: limit)
    }

    private func _searchPage(
        vector: [Float],
        threshold: Float,
        filter: VectorSearchFilter?,
        offset: Int,
        limit: Int
    ) throws(AdapterError) -> [ScoredResult] {
        let shard = try ensureShard()
        let edgeFilter = filter.map { filter in
            Filter(
                must: [.field(condition: FieldCondition(
                    key: VectorPayload.creationKey,
                    match: nil,
                    range: RangeFloat(gte: filter.creationRange.lowerBound, gt: nil, lte: filter.creationRange.upperBound, lt: nil),
                    geoBoundingBox: nil,
                    geoRadius: nil,
                    valuesCount: nil
                ))],
                should: nil,
                mustNot: nil
            )
        }
        do {
            let request = SearchRequest(
                query: .nearest(vector: vector, using: nil),
                limit: UInt64(limit),
                offset: UInt64(offset),
                filter: edgeFilter,
                // Exact search keeps the order stable across pages.
                params: SearchParams(hnswEf: nil, exact: true, indexedOnly: false),
                withVector: .bool(enable: false),
                withPayload: .bool(enable: true),
                scoreThreshold: Self.inclusiveThreshold(threshold)
            )
            return try shard.search(request: request).map { scored in
                ScoredResult(id: pointIdString(scored.id), score: scored.score, payloadJson: scored.payload, vectorJson: nil)
            }
        } catch {
            throw .vectorStore("Search failed: \(error.localizedDescription)")
        }
    }

    public nonisolated func vector(id: String) async throws(AdapterError) -> [Float]? {
        try await _vector(id: id)
    }

    private func _vector(id: String) throws(AdapterError) -> [Float]? {
        let shard = try ensureShard()
        let records: [Record]
        do {
            records = try shard.retrieve(pointIds: [.uuid(value: id)], withPayload: .bool(enable: false), withVector: .bool(enable: true))
        } catch {
            throw .vectorStore("Retrieve failed: \(error.localizedDescription)")
        }
        guard let json = records.first?.vector else { return nil }
        guard let vector = Self.decodeVector(json) else {
            throw .vectorStore("Unreadable vector for point \(id)")
        }
        return vector
    }

    /// Qdrant Edge treats `scoreThreshold` as exclusive (score > threshold); the domain rule is
    /// inclusive. No float lies strictly between `threshold.nextDown` and `threshold`, so this
    /// returns exactly the scores >= threshold without client-side filtering that could shorten pages.
    static func inclusiveThreshold(_ threshold: Float) -> Float {
        threshold.nextDown
    }

    /// Accepts a plain array or a single named vector (`{"": [...]}`).
    static func decodeVector(_ json: String) -> [Float]? {
        guard let data = json.data(using: .utf8) else { return nil }
        if let plain = try? JSONDecoder().decode([Float].self, from: data) {
            return plain
        }
        if let named = try? JSONDecoder().decode([String: [Float]].self, from: data), named.count == 1 {
            return named.values.first
        }
        return nil
    }

    public nonisolated func scroll(offset: String?, limit: Int) async throws(AdapterError) -> ScrollPage {
        try await _scroll(offset: offset, limit: limit)
    }

    private func _scroll(offset: String?, limit: Int) throws(AdapterError) -> ScrollPage {
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

    public nonisolated func delete(ids: [String]) async throws(AdapterError) {
        try await _delete(ids: ids)
    }

    private func _delete(ids: [String]) throws(AdapterError) {
        let shard = try ensureShard()
        let pointIds = ids.map { PointId.uuid(value: $0) }
        do {
            let operation = UpdateOperation.deletePoints(pointIds: pointIds)
            try shard.update(operation: operation)
        } catch {
            throw .vectorStore("Delete failed: \(error.localizedDescription)")
        }
    }

    public nonisolated func count() async throws(AdapterError) -> Int {
        try await _count()
    }

    private func _count() throws(AdapterError) -> Int {
        guard dimensions > 0 else { return 0 }
        let shard = try ensureShard()
        do {
            let result = try shard.count(request: CountRequest(filter: nil, exact: true))
            return Int(result)
        } catch {
            throw .vectorStore("Count failed: \(error.localizedDescription)")
        }
    }

    public nonisolated func close() async {
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
