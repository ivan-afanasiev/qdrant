import CoreGraphics
import Foundation

struct ScanPipeline {
    let photoLibrary: any PhotoLibraryProviding
    let embeddingService: any EmbeddingProviding
    let vectorStore: any VectorStoring
    let upsertBatchSize: Int = 20
    let maxConcurrency: Int = 4

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

                if let point = await embedAsset(asset) {
                    if !dimensionsPropagated {
                        await vectorStore.updateDimensions(point.vector.count)
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

    private func embedAsset(_ asset: PhotoAsset) async -> VectorPoint? {
        let thumbnailSize = CGSize(width: 224, height: 224)
        do {
            let image = try await photoLibrary.loadThumbnail(for: asset, size: thumbnailSize)
            let vector = try await embeddingService.embed(image: image)
            let uuid = deterministicUUID(from: asset.localIdentifier)
            let payload = assetPayloadJson(asset)
            return VectorPoint(id: uuid, vector: vector, payloadJson: payload)
        } catch {
            return nil
        }
    }

    private func assetPayloadJson(_ asset: PhotoAsset) -> String {
        let dateString = asset.creationDate.map {
            ISO8601DateFormatter().string(from: $0)
        } ?? "null"

        return """
        {"assetId":"\(asset.localIdentifier)","creationDate":"\(dateString)","pixelWidth":\(asset.pixelWidth),"pixelHeight":\(asset.pixelHeight)}
        """
    }
}
