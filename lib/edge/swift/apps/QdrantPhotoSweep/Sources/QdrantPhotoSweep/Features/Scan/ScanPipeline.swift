import CoreGraphics
import Foundation

struct ScanPipeline {
    let photoLibrary: any PhotoLibraryProviding
    let embeddingService: any EmbeddingProviding
    let vectorStore: any VectorStoring
    let scanStore: any ScanSessionStoring
    let configureDimensions: @Sendable (Int) async -> Void
    let upsertBatchSize: Int = 20

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

            var pendingBatch: [(assetLocalId: String, point: VectorPoint)] = []
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
                    pendingBatch.append((asset.localIdentifier, point))
                }
                await state.reduce(.batchCompleted(count: 1))

                if pendingBatch.count >= upsertBatchSize {
                    try await flushBatch(pendingBatch, sessionId: sessionId, dimensions: currentDimensions)
                    indexed += pendingBatch.count
                    pendingBatch.removeAll(keepingCapacity: true)
                }
            }

            if !pendingBatch.isEmpty {
                try await flushBatch(pendingBatch, sessionId: sessionId, dimensions: currentDimensions)
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

    private func flushBatch(_ batch: [(assetLocalId: String, point: VectorPoint)], sessionId: UUID, dimensions: Int) async throws {
        try await vectorStore.upsert(points: batch.map(\.point))
        for entry in batch {
            try? await scanStore.recordIndexedPhoto(
                sessionId: sessionId,
                assetLocalId: entry.assetLocalId,
                vectorUUID: entry.point.id,
                dimensions: dimensions
            )
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
