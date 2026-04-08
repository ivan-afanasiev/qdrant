import Foundation
import QdrantEdge

actor QdrantVectorStore: VectorStoring {
    private let basePath: String
    private var dimensions: Int
    private var shard: EdgeShard?
    private var dimensionMismatchMessage: String?

    init(path: String, dimensions: Int) {
        self.basePath = path
        self.dimensions = dimensions
    }

    func updateDimensions(_ dims: Int) {
        guard dims > 0 else { return }

        let previousDims = (try? String(contentsOf: markerURL, encoding: .utf8))
            .flatMap(Int.init)

        if let prev = previousDims, prev != dims {
            shard?.close()
            shard = nil
            if FileManager.default.fileExists(atPath: basePath) {
                dimensionMismatchMessage = "Stored vector dimensions (\(prev)) do not match current embeddings (\(dims)). Reset the database to rebuild the index."
                self.dimensions = dims
                return
            }
        }
        dimensionMismatchMessage = nil
        try? String(dims).write(to: markerURL, atomically: true, encoding: .utf8)

        self.dimensions = dims
    }

    func restoreDimensionsFromDisk() {
        if let stored = (try? String(contentsOf: markerURL, encoding: .utf8)).flatMap(Int.init), stored > 0 {
            self.dimensions = stored
        }
    }

    private var markerURL: URL {
        URL(fileURLWithPath: basePath)
            .deletingLastPathComponent()
            .appendingPathComponent("qdrant-edge-dims")
    }

    private func ensureShard() async throws(AppError) -> EdgeShard {
        if let existing = shard {
            return existing
        }
        if let mismatch = dimensionMismatchMessage {
            throw .vectorStore(mismatch)
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
            let loaded = try await loadShardWithRetry(config: config, maxAttempts: 3)
            shard = loaded
            return loaded
        } catch let error as AppError {
            throw error
        } catch {
            throw .vectorStore("Failed to load shard: \(error.localizedDescription)")
        }
    }

    private func loadShardWithRetry(config: EdgeConfig, maxAttempts: Int) async throws -> EdgeShard {
        var lastError: Error?
        for attempt in 0..<maxAttempts {
            do {
                return try EdgeShard.load(path: basePath, config: config)
            } catch {
                let message = error.localizedDescription
                let isTransientLock = message.contains("WouldBlock") || message.contains("Resource temporarily unavailable")
                guard isTransientLock, attempt < maxAttempts - 1 else {
                    lastError = error
                    break
                }
                lastError = error
                try await Task.sleep(for: .milliseconds((attempt + 1) * 500))
            }
        }
        throw AppError.vectorStore("Failed to load shard: \(lastError?.localizedDescription ?? "unknown")")
    }

    nonisolated func exists(id: String) async throws(AppError) -> Bool {
        try await _exists(id: id)
    }

    private func _exists(id: String) async throws(AppError) -> Bool {
        guard dimensions > 0 else { return false }
        let shard = try await ensureShard()
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

    nonisolated func upsert(points: [VectorPoint]) async throws(AppError) {
        try await _upsert(points: points)
    }

    private func _upsert(points: [VectorPoint]) async throws(AppError) {
        let shard = try await ensureShard()
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

    private func _search(vector: [Float], limit: Int, threshold: Float) async throws(AppError) -> [ScoredResult] {
        let shard = try await ensureShard()
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

    private func _scroll(offset: String?, limit: Int) async throws(AppError) -> ScrollPage {
        let shard = try await ensureShard()
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

    private func _delete(ids: [String]) async throws(AppError) {
        let shard = try await ensureShard()
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

    private func _count() async throws(AppError) -> Int {
        guard dimensions > 0 else { return 0 }
        let shard = try await ensureShard()
        do {
            let result = try shard.count(request: CountRequest(filter: nil, exact: true))
            return Int(result)
        } catch {
            throw .vectorStore("Count failed: \(error.localizedDescription)")
        }
    }

    nonisolated func reset() async throws(AppError) {
        try await _reset()
    }

    private func _reset() throws(AppError) {
        shard?.close()
        shard = nil
        dimensionMismatchMessage = nil
        dimensions = 0

        if FileManager.default.fileExists(atPath: basePath) {
            do {
                try FileManager.default.removeItem(atPath: basePath)
            } catch {
                throw .vectorStore("Failed to remove vector store: \(error.localizedDescription)")
            }
        }

        if FileManager.default.fileExists(atPath: markerURL.path) {
            do {
                try FileManager.default.removeItem(at: markerURL)
            } catch {
                throw .vectorStore("Failed to remove vector dimension marker: \(error.localizedDescription)")
            }
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
