import CoreGraphics
import Foundation

struct ScanPipeline {
    let photoLibrary: any PhotoLibraryProviding
    let embeddingService: any EmbeddingProviding
    let vectorStore: any VectorStoring
    let batchSize: Int = 50

    func run(dateRange: DateRange, state: ScanState) async {
        do {
            let assets = try await photoLibrary.fetchAssets(in: dateRange)
            state.reduce(.didStartScan(total: assets.count))

            var indexed = 0
            for batchStart in stride(from: 0, to: assets.count, by: batchSize) {
                guard !Task.isCancelled else {
                    state.reduce(.didTapCancel)
                    return
                }

                let batchEnd = min(batchStart + batchSize, assets.count)
                let batch = Array(assets[batchStart..<batchEnd])
                let points = await processBatch(batch)

                guard !Task.isCancelled else {
                    state.reduce(.didTapCancel)
                    return
                }

                guard !points.isEmpty else {
                    state.reduce(.batchCompleted(count: batch.count))
                    continue
                }

                try await vectorStore.upsert(points: points)
                indexed += points.count
                state.reduce(.batchCompleted(count: batch.count))
            }

            state.reduce(.didFinishScan(indexed: indexed))
        } catch {
            state.reduce(.didFail(error))
        }
    }

    private func processBatch(_ assets: [PhotoAsset]) async -> [VectorPoint] {
        await withTaskGroup(of: VectorPoint?.self, returning: [VectorPoint].self) { group in
            let thumbnailSize = CGSize(width: 224, height: 224)
            for asset in assets {
                group.addTask {
                    await embedAsset(asset, thumbnailSize: thumbnailSize)
                }
            }

            var results: [VectorPoint] = []
            for await result in group {
                guard let point = result else { continue }
                results.append(point)
            }
            return results
        }
    }

    private func embedAsset(_ asset: PhotoAsset, thumbnailSize: CGSize) async -> VectorPoint? {
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
