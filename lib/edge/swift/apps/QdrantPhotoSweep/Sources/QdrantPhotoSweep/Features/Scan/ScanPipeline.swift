import CoreGraphics
import Foundation

struct ScanPipeline {
    let photoLibrary: any PhotoLibraryProviding
    let embeddingService: any EmbeddingProviding
    let vectorStore: any VectorStoring
    let scanStore: any ScanSessionStoring
    let configureDimensions: @Sendable (Int) async -> Void
    let onGroupsUpdated: (@Sendable ([DuplicateGroup]) -> Void)?
    let similarityThreshold: Float
    let upsertBatchSize: Int = 20

    init(
        photoLibrary: any PhotoLibraryProviding,
        embeddingService: any EmbeddingProviding,
        vectorStore: any VectorStoring,
        scanStore: any ScanSessionStoring,
        configureDimensions: @Sendable @escaping (Int) async -> Void,
        similarityThreshold: Float = AppSettings.defaultSimilarityThreshold,
        onGroupsUpdated: (@Sendable ([DuplicateGroup]) -> Void)? = nil
    ) {
        self.photoLibrary = photoLibrary
        self.embeddingService = embeddingService
        self.vectorStore = vectorStore
        self.scanStore = scanStore
        self.configureDimensions = configureDimensions
        self.similarityThreshold = similarityThreshold
        self.onGroupsUpdated = onGroupsUpdated
    }

    private struct BatchEntry {
        let assetLocalId: String
        let point: VectorPoint
        let pixelWidth: Int
        let pixelHeight: Int
        let creationDate: Date?
    }

    func run(dateRange: DateRange, state: ScanState, resumeSessionId: UUID? = nil) async {
        do {
            let assets = try await photoLibrary.fetchAssets(in: dateRange)
            await state.reduce(.didStartScan(total: assets.count))

            let sessionId: UUID
            if let existing = resumeSessionId {
                try? await scanStore.updateSessionStatus(existing, status: .scanning, indexedPhotos: nil)
                sessionId = existing
            } else {
                sessionId = try await scanStore.createSession(
                    rangeStart: dateRange.start,
                    rangeEnd: dateRange.end,
                    totalPhotos: assets.count
                )
            }

            var pendingBatch: [BatchEntry] = []
            var indexed = 0
            var dimensionsPropagated = false
            var currentDimensions = 0

            for asset in assets {
                guard !Task.isCancelled else {
                    try? await scanStore.updateSessionStatus(sessionId, status: .interrupted, indexedPhotos: indexed)
                    await state.reduce(.didTapCancel)
                    return
                }

                let pointId = deterministicUUID(from: asset.localIdentifier)
                let alreadyIndexed = try await vectorStore.exists(id: pointId)
                guard !alreadyIndexed else {
                    indexed += 1
                    await state.reduce(.batchCompleted(count: 1))
                    continue
                }

                if let point = await embedAsset(asset, id: pointId) {
                    if !dimensionsPropagated {
                        currentDimensions = point.vector.count
                        await configureDimensions(currentDimensions)
                        dimensionsPropagated = true
                    }
                    pendingBatch.append(BatchEntry(
                        assetLocalId: asset.localIdentifier,
                        point: point,
                        pixelWidth: asset.pixelWidth,
                        pixelHeight: asset.pixelHeight,
                        creationDate: asset.creationDate
                    ))
                }
                await state.reduce(.batchCompleted(count: 1))

                if pendingBatch.count >= upsertBatchSize {
                    try await flushBatchWithDetection(
                        pendingBatch,
                        sessionId: sessionId,
                        dimensions: currentDimensions
                    )
                    indexed += pendingBatch.count
                    pendingBatch.removeAll(keepingCapacity: true)
                }
            }

            if !pendingBatch.isEmpty {
                try await flushBatchWithDetection(
                    pendingBatch,
                    sessionId: sessionId,
                    dimensions: currentDimensions
                )
                indexed += pendingBatch.count
            }

            try? await scanStore.updateSessionStatus(sessionId, status: .completed, indexedPhotos: indexed)
            await state.reduce(.didFinishScan(indexed: indexed))
        } catch let appError as AppError {
            await state.reduce(.didFail(appError))
        } catch {
            await state.reduce(.didFail(.unknown(error.localizedDescription)))
        }
    }

    private func flushBatchWithDetection(
        _ batch: [BatchEntry],
        sessionId: UUID,
        dimensions: Int
    ) async throws {
        try await vectorStore.upsert(points: batch.map(\.point))

        for entry in batch {
            try? await scanStore.recordIndexedPhoto(
                sessionId: sessionId,
                assetLocalId: entry.assetLocalId,
                vectorUUID: entry.point.id,
                dimensions: dimensions,
                pixelWidth: entry.pixelWidth,
                pixelHeight: entry.pixelHeight,
                creationDate: entry.creationDate
            )
        }

        var foundEdges = false
        for entry in batch {
            guard !Task.isCancelled else { return }

            let results = try await vectorStore.search(
                vector: entry.point.vector,
                limit: 10,
                threshold: similarityThreshold
            )

            for result in results where result.id != entry.point.id {
                try? await scanStore.recordSimilarityEdge(
                    source: entry.point.id,
                    target: result.id,
                    score: result.score,
                    sessionId: sessionId
                )
                foundEdges = true
            }
        }

        if foundEdges, let callback = onGroupsUpdated {
            let groups = try? await scanStore.computeGroupsFromEdges(sessionId: sessionId)
            if let groups, !groups.isEmpty {
                callback(groups)
            }
        }
    }

    private func embedAsset(_ asset: PhotoAsset, id: String) async -> VectorPoint? {
        let thumbnailSize = CGSize(width: 224, height: 224)
        do {
            let image = try await photoLibrary.loadThumbnail(for: asset, size: thumbnailSize)
            let vector = try await embeddingService.embed(image: image)
            let payload = assetPayloadJson(asset)
            return VectorPoint(id: id, vector: vector, payloadJson: payload)
        } catch {
            return nil
        }
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
