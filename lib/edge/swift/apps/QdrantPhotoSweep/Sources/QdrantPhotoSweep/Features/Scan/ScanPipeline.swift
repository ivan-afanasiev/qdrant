import CoreGraphics
import Foundation

struct ScanOutcome: Sendable {
    enum Status: Sendable {
        case completed
        case interrupted
        case failed(AppError)
    }

    let sessionId: UUID?
    let status: Status
    let groupsFound: Int

    var succeeded: Bool {
        if case .completed = status { return true }
        return false
    }
}

struct ScanPipeline {
    let photoLibrary: any PhotoLibraryProviding
    let embeddingService: any EmbeddingProviding
    let vectorStore: any VectorStoring
    let scanStore: any ScanSessionStoring
    let configureDimensions: @Sendable (Int) async -> Void
    let onGroupCountChanged: (@Sendable (Int) -> Void)?
    let onSessionStarted: (@Sendable (UUID) async -> Void)?
    let similarityThreshold: Float
    let upsertBatchSize: Int = 20

    init(
        photoLibrary: any PhotoLibraryProviding,
        embeddingService: any EmbeddingProviding,
        vectorStore: any VectorStoring,
        scanStore: any ScanSessionStoring,
        configureDimensions: @Sendable @escaping (Int) async -> Void,
        similarityThreshold: Float = AppSettings.defaultSimilarityThreshold,
        onGroupCountChanged: (@Sendable (Int) -> Void)? = nil,
        onSessionStarted: (@Sendable (UUID) async -> Void)? = nil
    ) {
        self.photoLibrary = photoLibrary
        self.embeddingService = embeddingService
        self.vectorStore = vectorStore
        self.scanStore = scanStore
        self.configureDimensions = configureDimensions
        self.similarityThreshold = similarityThreshold
        self.onGroupCountChanged = onGroupCountChanged
        self.onSessionStarted = onSessionStarted
    }

    private struct BatchEntry {
        let assetLocalId: String
        let point: VectorPoint
        let pixelWidth: Int
        let pixelHeight: Int
        let creationDate: Date?
    }

    func run(dateRange: DateRange, state: ScanState, resumeSessionId: UUID? = nil) async -> ScanOutcome {
        var sessionId = resumeSessionId
        var indexed = 0
        var groupCount = 0
        do {
            try Task.checkCancellation()
            let assets = try await photoLibrary.fetchAssets(in: dateRange)
            try Task.checkCancellation()
            await state.reduce(.didStartScan(total: assets.count))

            let activeSessionId: UUID
            if let existing = resumeSessionId {
                try await scanStore.updateSessionStatus(existing, status: .scanning, indexedPhotos: nil)
                activeSessionId = existing
            } else {
                activeSessionId = try await scanStore.createSession(
                    rangeStart: dateRange.start, rangeEnd: dateRange.end, totalPhotos: assets.count
                )
            }
            sessionId = activeSessionId
            await onSessionStarted?(activeSessionId)

            var pendingBatch: [BatchEntry] = []
            var dimensionsPropagated = false
            var currentDimensions = 0
            var hadEmbeddingFailures = false

            for asset in assets {
                try Task.checkCancellation()
                let pointId = deterministicUUID(from: asset.localIdentifier)
                let exists = try await vectorStore.exists(id: pointId)
                let detectionComplete = try await scanStore.isDetectionComplete(
                    vectorUUID: pointId, threshold: similarityThreshold
                )
                if exists && detectionComplete {
                    indexed += 1
                    await state.reduce(.batchCompleted(count: 1))
                    continue
                }

                // Re-embedding also repairs points upserted before an interrupted metadata/search write.
                do {
                    let image = try await photoLibrary.loadThumbnail(
                        for: asset, size: CGSize(width: 224, height: 224)
                    )
                    try Task.checkCancellation()
                    let vector = try await embeddingService.embed(image: image)
                    try Task.checkCancellation()
                    if !dimensionsPropagated {
                        currentDimensions = vector.count
                        await configureDimensions(currentDimensions)
                        dimensionsPropagated = true
                    }
                    pendingBatch.append(BatchEntry(
                        assetLocalId: asset.localIdentifier,
                        point: VectorPoint(id: pointId, vector: vector, payloadJson: assetPayloadJson(asset)),
                        pixelWidth: asset.pixelWidth,
                        pixelHeight: asset.pixelHeight,
                        creationDate: asset.creationDate
                    ))
                } catch {
                    try Task.checkCancellation()
                    hadEmbeddingFailures = true
                }
                await state.reduce(.batchCompleted(count: 1))

                if pendingBatch.count >= upsertBatchSize {
                    groupCount = try await flushBatchWithDetection(
                        pendingBatch, sessionId: activeSessionId, dimensions: currentDimensions
                    )
                    indexed += pendingBatch.count
                    pendingBatch.removeAll(keepingCapacity: true)
                }
            }
            if !pendingBatch.isEmpty {
                groupCount = try await flushBatchWithDetection(
                    pendingBatch, sessionId: activeSessionId, dimensions: currentDimensions
                )
                indexed += pendingBatch.count
            }
            try Task.checkCancellation()
            if hadEmbeddingFailures {
                throw AppError.embedding("Some photos could not be processed. The scan can be resumed.")
            }
            try await scanStore.updateSessionStatus(activeSessionId, status: .completed, indexedPhotos: indexed)
            await state.reduce(.didFinishScan(indexed: indexed))
            return ScanOutcome(sessionId: sessionId, status: .completed, groupsFound: groupCount)
        } catch {
            if let sessionId {
                do {
                    try await scanStore.updateSessionStatus(sessionId, status: .interrupted, indexedPhotos: indexed)
                } catch {
                    AppLog.scan.error("Unable to checkpoint interrupted scan: \(error)")
                }
            }
            if Task.isCancelled || error is CancellationError {
                await state.reduce(.didTapCancel)
                return ScanOutcome(sessionId: sessionId, status: .interrupted, groupsFound: groupCount)
            }
            let appError = error as? AppError ?? .unknown(error.localizedDescription)
            await state.reduce(.didFail(appError))
            return ScanOutcome(sessionId: sessionId, status: .failed(appError), groupsFound: groupCount)
        }
    }

    private func flushBatchWithDetection(
        _ batch: [BatchEntry], sessionId: UUID, dimensions: Int
    ) async throws -> Int {
        try Task.checkCancellation()
        try await vectorStore.upsert(points: batch.map(\.point))
        for entry in batch {
            try Task.checkCancellation()
            try await scanStore.recordIndexedPhoto(
                sessionId: sessionId,
                assetLocalId: entry.assetLocalId,
                vectorUUID: entry.point.id,
                dimensions: dimensions,
                pixelWidth: entry.pixelWidth,
                pixelHeight: entry.pixelHeight,
                creationDate: entry.creationDate
            )
        }
        for entry in batch {
            try Task.checkCancellation()
            let results = try await vectorStore.search(
                vector: entry.point.vector, limit: 10, threshold: similarityThreshold
            )
            for result in results where result.id != entry.point.id {
                try Task.checkCancellation()
                try await scanStore.recordSimilarityEdge(
                    source: entry.point.id, target: result.id, score: result.score, sessionId: sessionId
                )
            }
        }
        try Task.checkCancellation()
        // Recompute even when this retry found no new matches: a previous run may have saved edges.
        let groups = try await scanStore.computeGroupsFromEdges(sessionId: sessionId)
        try Task.checkCancellation()
        try await scanStore.markDetectionComplete(
            vectorUUIDs: batch.map { $0.point.id }, threshold: similarityThreshold
        )
        onGroupCountChanged?(groups.count)
        return groups.count
    }

    private static let isoFormatter = ISO8601DateFormatter()

    private struct AssetPayload: Encodable {
        let assetId: String
        let creationDate: String?
        let pixelWidth: Int
        let pixelHeight: Int
    }

    private func assetPayloadJson(_ asset: PhotoAsset) -> String {
        let dateString = asset.creationDate.map { Self.isoFormatter.string(from: $0) }
        let payload = AssetPayload(
            assetId: asset.localIdentifier,
            creationDate: dateString,
            pixelWidth: asset.pixelWidth,
            pixelHeight: asset.pixelHeight
        )
        guard let data = try? JSONEncoder().encode(payload),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }
}
