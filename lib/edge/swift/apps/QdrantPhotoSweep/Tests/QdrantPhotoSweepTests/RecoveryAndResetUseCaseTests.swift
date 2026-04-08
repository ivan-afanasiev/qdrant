import XCTest
@testable import QdrantPhotoSweep

final class RecoveryAndResetUseCaseTests: XCTestCase {
    func testLoadInitialStateRecoversPendingOperationsBeforeInspectingState() async throws {
        let scanStore = RecoveryScanStore()
        scanStore.pendingGroupCountValue = 2
        let useCase = LoadInitialStateUseCase(scanStore: scanStore, settings: AppSettings())

        let action = try await useCase.execute(())

        XCTAssertEqual(scanStore.events, ["recover", "latestInterrupted", "pendingCount"])
        switch action {
        case .reviewPending:
            XCTAssertTrue(true)
        default:
            XCTFail("Expected pending review flow")
        }
    }

    func testClearDatabaseUseCaseResetsBothStores() async throws {
        let vectorStore = ResetVectorStore()
        let scanStore = ResetScanStore()
        let useCase = ClearDatabaseUseCase(vectorStore: vectorStore, scanStore: scanStore)

        try await useCase.execute(())

        XCTAssertEqual(scanStore.resetCount, 1)
        XCTAssertEqual(vectorStore.resetCount, 1)
    }
}

private final class RecoveryScanStore: ScanSessionStoring, @unchecked Sendable {
    var events: [String] = []
    var pendingGroupCountValue = 0

    func createSession(rangeStart: Date, rangeEnd: Date, totalPhotos: Int) async throws -> UUID { UUID() }
    func updateSessionStatus(_ sessionId: UUID, status: ScanSessionStatus, indexedPhotos: Int?) async throws {}
    func latestCompletedSession() async throws -> ScanSessionDTO? { nil }
    func latestInterruptedSession() async throws -> ScanSessionDTO? {
        events.append("latestInterrupted")
        return nil
    }
    func interruptActiveSessions() async throws {}
    func claimSessionLease(sessionId: UUID, owner: String, until: Date) async throws -> Bool { true }
    func persistScanBatch(sessionId: UUID, photos: [ScanPhotoRecord], similarityEdges: [SimilarityEdgeRecord]) async throws -> PersistScanBatchResult {
        PersistScanBatchResult(groups: [])
    }
    func loadPendingGroups() async throws -> [DuplicateGroupDTO] { [] }
    func loadPendingGroupsPage(offset: Int, limit: Int) async throws -> [DuplicateGroupDTO] { [] }
    func loadPendingGroup(id: UUID) async throws -> DuplicateGroupDTO? { nil }
    func loadNextPendingGroup() async throws -> DuplicateGroupDTO? { nil }
    func pendingGroupCount() async throws -> Int {
        events.append("pendingCount")
        return pendingGroupCountValue
    }
    func markGroupReviewed(groupId: UUID, keptVectorUUIDs: Set<String>) async throws {}
    func markGroupDeletionPending(groupId: UUID, keptVectorUUIDs: Set<String>, deletedVectorUUIDs: Set<String>) async throws {}
    func markGroupDeletionFailed(groupId: UUID, reason: String, deletedVectorUUIDs: Set<String>) async throws {}
    func markGroupDeleted(groupId: UUID, keptVectorUUIDs: Set<String>, deletedVectorUUIDs: Set<String>) async throws {}
    func recoverPendingOperations() async throws { events.append("recover") }
    func resetAllData() async throws {}
    func countNewPhotosSince(date: Date, in dateRange: DateRange, using photoLibrary: any PhotoLibraryProviding) async throws -> Int { 0 }
    func totalPhotosIndexed() async throws -> Int { 0 }
    func totalDuplicateGroupsFound() async throws -> Int { 0 }
    func totalPhotosDeleted() async throws -> Int { 0 }
}

private final class ResetVectorStore: VectorStoring, @unchecked Sendable {
    var resetCount = 0

    func exists(id: String) async throws(AppError) -> Bool { false }
    func upsert(points: [VectorPoint]) async throws(AppError) {}
    func search(vector: [Float], limit: Int, threshold: Float) async throws(AppError) -> [ScoredResult] { [] }
    func scroll(offset: String?, limit: Int) async throws(AppError) -> ScrollPage { ScrollPage(records: [], nextOffset: nil) }
    func delete(ids: [String]) async throws(AppError) {}
    func count() async throws(AppError) -> Int { 0 }
    func reset() async throws(AppError) { resetCount += 1 }
    func close() async {}
}

private final class ResetScanStore: ScanSessionStoring, @unchecked Sendable {
    var resetCount = 0

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
    func markGroupDeletionPending(groupId: UUID, keptVectorUUIDs: Set<String>, deletedVectorUUIDs: Set<String>) async throws {}
    func markGroupDeletionFailed(groupId: UUID, reason: String, deletedVectorUUIDs: Set<String>) async throws {}
    func markGroupDeleted(groupId: UUID, keptVectorUUIDs: Set<String>, deletedVectorUUIDs: Set<String>) async throws {}
    func recoverPendingOperations() async throws {}
    func resetAllData() async throws { resetCount += 1 }
    func countNewPhotosSince(date: Date, in dateRange: DateRange, using photoLibrary: any PhotoLibraryProviding) async throws -> Int { 0 }
    func totalPhotosIndexed() async throws -> Int { 0 }
    func totalDuplicateGroupsFound() async throws -> Int { 0 }
    func totalPhotosDeleted() async throws -> Int { 0 }
}
