import CoreGraphics
import Foundation

struct ScanPipeline {
    let photoLibrary: any PhotoLibraryProviding
    let embeddingService: any EmbeddingProviding
    let vectorStore: any VectorStoring
    let scanStore: any ScanSessionStoring
    let configureDimensions: @Sendable (Int) async -> Void
    let onGroupCountChanged: (@Sendable (Int) -> Void)?
    let similarityThreshold: Float
    let ownerID: String
    let upsertBatchSize: Int = 20

    init(
        photoLibrary: any PhotoLibraryProviding,
        embeddingService: any EmbeddingProviding,
        vectorStore: any VectorStoring,
        scanStore: any ScanSessionStoring,
        configureDimensions: @Sendable @escaping (Int) async -> Void,
        ownerID: String,
        similarityThreshold: Float = AppSettings.defaultSimilarityThreshold,
        onGroupCountChanged: (@Sendable (Int) -> Void)? = nil
    ) {
        self.photoLibrary = photoLibrary
        self.embeddingService = embeddingService
        self.vectorStore = vectorStore
        self.scanStore = scanStore
        self.configureDimensions = configureDimensions
        self.ownerID = ownerID
        self.similarityThreshold = similarityThreshold
        self.onGroupCountChanged = onGroupCountChanged
    }

    private struct BatchEntry {
        let assetLocalId: String
        let point: VectorPoint
        let dimensions: Int
        let pixelWidth: Int
        let pixelHeight: Int
        let creationDate: Date?
    }

    private enum AssetProcessingResult {
        case skipped(ScanPhotoRecord)
        case batched(BatchEntry)
        case failed(ScanPhotoRecord)
    }

    func run(dateRange: DateRange, state: ScanState, resumeSessionId: UUID? = nil) async {
        var activeSessionId = resumeSessionId
        do {
            let assets = try await photoLibrary.fetchAssets(in: dateRange)

            let sessionId: UUID
            var indexed = 0
            if let existing = resumeSessionId {
                let existingSession = try await scanStore.loadSession(id: existing)
                let resumedProcessed = min(
                    assets.count,
                    (existingSession?.indexedPhotos ?? 0)
                        + (existingSession?.skippedPhotos ?? 0)
                        + (existingSession?.failedPhotos ?? 0)
                )
                indexed = min(
                    assets.count,
                    (existingSession?.indexedPhotos ?? 0) + (existingSession?.skippedPhotos ?? 0)
                )
                await state.reduce(.didResumeScan(processed: resumedProcessed, total: assets.count))
                try? await scanStore.updateSessionStatus(existing, status: .scanning, indexedPhotos: nil)
                sessionId = existing
            } else {
                await state.reduce(.didStartScan(total: assets.count))
                sessionId = try await scanStore.createSession(
                    rangeStart: dateRange.start,
                    rangeEnd: dateRange.end,
                    totalPhotos: assets.count
                )
            }
            activeSessionId = sessionId
            try await claimLease(for: sessionId)

            var pendingBatch: [BatchEntry] = []
            var pendingRecords: [ScanPhotoRecord] = []
            var processedSinceFlush = 0

            for asset in assets {
                guard !Task.isCancelled else {
                    try? await scanStore.updateSessionStatus(sessionId, status: .interrupted, indexedPhotos: indexed)
                    await state.reduce(.didTapCancel)
                    return
                }

                switch try await processAsset(asset) {
                case .skipped(let record):
                    pendingRecords.append(record)
                    indexed += 1
                case .batched(let batchEntry):
                    pendingBatch.append(batchEntry)
                case .failed(let record):
                    pendingRecords.append(record)
                }

                await state.reduce(.batchCompleted(count: 1))
                processedSinceFlush += 1

                if processedSinceFlush >= upsertBatchSize {
                    indexed += try await flushBatchWithDetection(
                        batch: &pendingBatch,
                        records: &pendingRecords,
                        sessionId: sessionId
                    )
                    processedSinceFlush = 0
                }
            }

            if !pendingBatch.isEmpty || !pendingRecords.isEmpty {
                indexed += try await flushBatchWithDetection(
                    batch: &pendingBatch,
                    records: &pendingRecords,
                    sessionId: sessionId
                )
            }

            try await scanStore.updateSessionStatus(sessionId, status: .completed, indexedPhotos: indexed)
            await state.reduce(.didFinishScan(indexed: indexed))
        } catch let appError as AppError {
            if let sessionId = activeSessionId {
                try? await scanStore.updateSessionStatus(sessionId, status: .failed, indexedPhotos: nil)
            }
            await state.reduce(.didFail(appError))
        } catch {
            if let sessionId = activeSessionId {
                try? await scanStore.updateSessionStatus(sessionId, status: .failed, indexedPhotos: nil)
            }
            await state.reduce(.didFail(.unknown(error.localizedDescription)))
        }
    }

    private func processAsset(_ asset: PhotoAsset) async throws -> AssetProcessingResult {
        let pointId = deterministicUUID(from: asset.localIdentifier)
        if try await vectorStore.exists(id: pointId) {
            return .skipped(ScanPhotoRecord(
                assetLocalId: asset.localIdentifier,
                vectorUUID: pointId,
                status: .skipped,
                embeddingDimensions: 0,
                pixelWidth: asset.pixelWidth,
                pixelHeight: asset.pixelHeight,
                creationDate: asset.creationDate,
                lastError: nil
            ))
        }

        let thumbnailSize = CGSize(width: 224, height: 224)
        do {
            let image = try await photoLibrary.loadThumbnail(for: asset, size: thumbnailSize)
            let vector = try await embeddingService.embed(image: image)
            await configureDimensions(vector.count)
            return .batched(BatchEntry(
                assetLocalId: asset.localIdentifier,
                point: VectorPoint(
                    id: pointId,
                    vector: vector,
                    payloadJson: assetPayloadJson(asset)
                ),
                dimensions: vector.count,
                pixelWidth: asset.pixelWidth,
                pixelHeight: asset.pixelHeight,
                creationDate: asset.creationDate
            ))
        } catch {
            let appError = error as? AppError ?? .unknown(error.localizedDescription)
            return .failed(ScanPhotoRecord(
                assetLocalId: asset.localIdentifier,
                vectorUUID: pointId,
                status: .failed,
                embeddingDimensions: 0,
                pixelWidth: asset.pixelWidth,
                pixelHeight: asset.pixelHeight,
                creationDate: asset.creationDate,
                lastError: appError.localizedDescription
            ))
        }
    }

    private func flushBatchWithDetection(
        batch: inout [BatchEntry],
        records: inout [ScanPhotoRecord],
        sessionId: UUID
    ) async throws -> Int {
        guard !batch.isEmpty || !records.isEmpty else { return 0 }

        let upsertedPoints = batch.map(\.point)
        if !upsertedPoints.isEmpty {
            try await vectorStore.upsert(points: upsertedPoints)
        }

        do {
            var edges: [SimilarityEdgeRecord] = []
            if !batch.isEmpty {
                for entry in batch {
                    guard !Task.isCancelled else { break }
                    let results = try await vectorStore.search(
                        vector: entry.point.vector,
                        limit: 10,
                        threshold: similarityThreshold
                    )

                    for result in results where result.id != entry.point.id {
                        edges.append(SimilarityEdgeRecord(
                            sourceVectorUUID: entry.point.id,
                            targetVectorUUID: result.id,
                            score: result.score
                        ))
                    }
                }
            }

            let indexedRecords = batch.map { entry in
                ScanPhotoRecord(
                    assetLocalId: entry.assetLocalId,
                    vectorUUID: entry.point.id,
                    status: .indexed,
                    embeddingDimensions: entry.dimensions,
                    pixelWidth: entry.pixelWidth,
                    pixelHeight: entry.pixelHeight,
                    creationDate: entry.creationDate,
                    lastError: nil
                )
            }

            let result = try await scanStore.persistScanBatch(
                sessionId: sessionId,
                photos: indexedRecords + records,
                similarityEdges: edges
            )
            try await claimLease(for: sessionId)

            if let callback = onGroupCountChanged, !result.groups.isEmpty {
                callback(result.groups.count)
            }

            let indexedCount = indexedRecords.count + records.filter { $0.status == .skipped }.count
            batch.removeAll(keepingCapacity: true)
            records.removeAll(keepingCapacity: true)
            return indexedCount
        } catch {
            if !upsertedPoints.isEmpty {
                try? await vectorStore.delete(ids: upsertedPoints.map(\.id))
            }
            throw error
        }
    }

    private func claimLease(for sessionId: UUID) async throws {
        let leaseUntil = Date().addingTimeInterval(120)
        let claimed = try await scanStore.claimSessionLease(
            sessionId: sessionId,
            owner: ownerID,
            until: leaseUntil
        )
        guard claimed else {
            throw AppError.unknown("Scan session is already owned by another worker")
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
