import CoreGraphics
import XCTest
@testable import QdrantPhotoSweep

final class DeleteGroupUseCaseTests: XCTestCase {
    func testDeleteGroupMarksPendingBeforeExternalDeletionAndCompletesOnSuccess() async throws {
        let photoLibrary = RecordingPhotoLibrary()
        let vectorStore = RecordingVectorStore()
        let scanStore = RecordingScanStore()
        let useCase = DeleteGroupUseCase(
            photoLibrary: photoLibrary,
            vectorStore: vectorStore,
            scanStore: scanStore
        )

        let group = makeGroup()
        let keptIds: Set<String> = ["keep-vector"]
        let output = try await useCase.execute(DeleteGroupInput(group: group, keptIds: keptIds))

        XCTAssertEqual(output.deleted, 1)
        XCTAssertEqual(output.kept, 1)
        XCTAssertEqual(
            scanStore.events,
            [
                "pending:\(group.id)",
                "deleted:\(group.id)",
            ]
        )
        XCTAssertEqual(vectorStore.deletedIDs, [[deterministicUUID(from: "delete-asset")]])
        XCTAssertEqual(photoLibrary.deletedAssetIDs, [["delete-asset"]])
    }

    func testDeleteGroupRecordsFailureForRecovery() async {
        let photoLibrary = RecordingPhotoLibrary()
        photoLibrary.deleteError = .deletion("Photos delete failed")
        let vectorStore = RecordingVectorStore()
        let scanStore = RecordingScanStore()
        let useCase = DeleteGroupUseCase(
            photoLibrary: photoLibrary,
            vectorStore: vectorStore,
            scanStore: scanStore
        )
        let group = makeGroup(id: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")

        do {
            _ = try await useCase.execute(DeleteGroupInput(group: group, keptIds: ["keep-vector"]))
            XCTFail("Expected deletion to fail")
        } catch {
            let appError = error as? AppError
            XCTAssertEqual(appError, .deletion("Photos delete failed"))
        }

        XCTAssertEqual(scanStore.events.count, 2)
        XCTAssertEqual(scanStore.events.first, "pending:\(group.id)")
        XCTAssertEqual(scanStore.events.last, "failed:\(group.id)")
    }

    private func makeGroup(id: String = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa") -> DuplicateGroup {
        let keep = PhotoReference(
            id: "keep-vector",
            assetId: "keep-asset",
            creationDate: nil,
            pixelWidth: 3000,
            pixelHeight: 2000,
            score: 0.99
        )
        let delete = PhotoReference(
            id: deterministicUUID(from: "delete-asset"),
            assetId: "delete-asset",
            creationDate: nil,
            pixelWidth: 1000,
            pixelHeight: 1000,
            score: 0.97
        )
        return DuplicateGroup(id: id, photos: [keep, delete], bestCandidate: keep)
    }
}

private final class RecordingPhotoLibrary: PhotoLibraryProviding, @unchecked Sendable {
    var deletedAssetIDs: [[String]] = []
    var deleteError: AppError?

    func requestAuthorization() async throws(AppError) {}
    func fetchAssets(in dateRange: DateRange) async throws(AppError) -> [PhotoAsset] { [] }
    func countAssets(in dateRange: DateRange) async throws(AppError) -> Int { 0 }
    func loadThumbnail(for asset: PhotoAsset, size: CGSize) async throws(AppError) -> CGImage {
        throw .photoLibrary("unused")
    }
    func loadFullImage(for asset: PhotoAsset) async throws(AppError) -> CGImage {
        throw .photoLibrary("unused")
    }
    func deleteAssets(_ identifiers: [String]) async throws(AppError) {
        deletedAssetIDs.append(identifiers)
        if let deleteError {
            throw deleteError
        }
    }
}

private final class RecordingVectorStore: VectorStoring, @unchecked Sendable {
    var deletedIDs: [[String]] = []

    func exists(id: String) async throws(AppError) -> Bool { false }
    func upsert(points: [VectorPoint]) async throws(AppError) {}
    func search(vector: [Float], limit: Int, threshold: Float) async throws(AppError) -> [ScoredResult] { [] }
    func scroll(offset: String?, limit: Int) async throws(AppError) -> ScrollPage { ScrollPage(records: [], nextOffset: nil) }
    func delete(ids: [String]) async throws(AppError) { deletedIDs.append(ids) }
    func count() async throws(AppError) -> Int { 0 }
    func reset() async throws(AppError) {}
    func close() async {}
}

private final class RecordingScanStore: ScanSessionStoring, @unchecked Sendable {
    var events: [String] = []

    func createSession(rangeStart: Date, rangeEnd: Date, totalPhotos: Int) async throws -> UUID { UUID() }
    func updateSessionStatus(_ sessionId: UUID, status: ScanSessionStatus, indexedPhotos: Int?) async throws {}
    func latestCompletedSession() async throws -> ScanSessionDTO? { nil }
    func latestInterruptedSession() async throws -> ScanSessionDTO? { nil }
    func interruptActiveSessions() async throws {}
    func claimSessionLease(sessionId: UUID, owner: String, until: Date) async throws -> Bool { true }
    func persistScanBatch(sessionId: UUID, photos: [ScanPhotoRecord], similarityEdges: [SimilarityEdgeRecord]) async throws -> PersistScanBatchResult {
        PersistScanBatchResult(groups: [])
    }
    func loadPendingGroups() async throws -> [DuplicateGroupDTO] { [] }
    func loadPendingGroupsPage(offset: Int, limit: Int) async throws -> [DuplicateGroupDTO] { [] }
    func loadPendingGroup(id: UUID) async throws -> DuplicateGroupDTO? { nil }
    func loadNextPendingGroup() async throws -> DuplicateGroupDTO? { nil }
    func pendingGroupCount() async throws -> Int { 0 }
    func markGroupReviewed(groupId: UUID, keptVectorUUIDs: Set<String>) async throws {}
    func markGroupDeletionPending(groupId: UUID, keptVectorUUIDs: Set<String>, deletedVectorUUIDs: Set<String>) async throws {
        events.append("pending:\(groupId.uuidString)")
    }
    func markGroupDeletionFailed(groupId: UUID, reason: String, deletedVectorUUIDs: Set<String>) async throws {
        events.append("failed:\(groupId.uuidString)")
    }
    func markGroupDeleted(groupId: UUID, keptVectorUUIDs: Set<String>, deletedVectorUUIDs: Set<String>) async throws {
        events.append("deleted:\(groupId.uuidString)")
    }
    func recoverPendingOperations() async throws {}
    func resetAllData() async throws {}
    func countNewPhotosSince(date: Date, in dateRange: DateRange, using photoLibrary: any PhotoLibraryProviding) async throws -> Int { 0 }
    func totalPhotosIndexed() async throws -> Int { 0 }
    func totalDuplicateGroupsFound() async throws -> Int { 0 }
    func totalPhotosDeleted() async throws -> Int { 0 }
}
