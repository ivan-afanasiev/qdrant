import CoreGraphics
import Foundation

struct ScanPipeline {
    let photoLibrary: any PhotoLibraryProviding
    let embeddingService: any EmbeddingProviding
    let vectorStore: any VectorStoring
    let configureDimensions: @Sendable (Int) async -> Void
    let upsertBatchSize: Int = 20

    func run(dateRange: DateRange, state: ScanState) async {
        do {
            let assets = try await photoLibrary.fetchAssets(in: dateRange)
            await state.reduce(.didStartScan(total: assets.count))

            var pendingPoints: [VectorPoint] = []
            var indexed = 0
            var dimensionsPropagated = false

            for asset in assets {
                guard !Task.isCancelled else {
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
                        await configureDimensions(point.vector.count)
                        dimensionsPropagated = true
                    }
                    pendingPoints.append(point)
                }
                await state.reduce(.batchCompleted(count: 1))

                if pendingPoints.count >= upsertBatchSize {
                    try await vectorStore.upsert(points: pendingPoints)
                    indexed += pendingPoints.count
                    pendingPoints.removeAll(keepingCapacity: true)
                }
            }

            if !pendingPoints.isEmpty {
                try await vectorStore.upsert(points: pendingPoints)
                indexed += pendingPoints.count
            }

            await state.reduce(.didFinishScan(indexed: indexed))
        } catch {
            await state.reduce(.didFail(error))
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
