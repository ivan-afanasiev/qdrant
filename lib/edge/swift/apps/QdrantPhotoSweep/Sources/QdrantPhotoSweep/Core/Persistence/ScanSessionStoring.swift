import Foundation

protocol ScanSessionStoring: Sendable {
    func createSession(rangeStart: Date, rangeEnd: Date, totalPhotos: Int) async throws -> UUID
    func loadSession(id: UUID) async throws -> ScanSessionDTO?
    func updateSessionStatus(_ sessionId: UUID, status: ScanSessionStatus, indexedPhotos: Int?) async throws
    func latestCompletedSession() async throws -> ScanSessionDTO?
    func latestInterruptedSession() async throws -> ScanSessionDTO?
    func interruptActiveSessions() async throws
    func claimSessionLease(sessionId: UUID, owner: String, until: Date) async throws -> Bool

    func persistScanBatch(
        sessionId: UUID,
        photos: [ScanPhotoRecord],
        similarityEdges: [SimilarityEdgeRecord]
    ) async throws -> PersistScanBatchResult

    func loadPendingGroups() async throws -> [DuplicateGroupDTO]
    func loadPendingGroupsPage(offset: Int, limit: Int) async throws -> [DuplicateGroupDTO]
    func loadPendingGroup(id: UUID) async throws -> DuplicateGroupDTO?
    func loadNextPendingGroup() async throws -> DuplicateGroupDTO?
    func pendingGroupCount() async throws -> Int
    func markGroupReviewed(groupId: UUID, keptVectorUUIDs: Set<String>) async throws
    func markGroupDeletionPending(groupId: UUID, keptVectorUUIDs: Set<String>, deletedVectorUUIDs: Set<String>) async throws
    func markGroupDeletionFailed(groupId: UUID, reason: String, deletedVectorUUIDs: Set<String>) async throws
    func markGroupDeleted(groupId: UUID, keptVectorUUIDs: Set<String>, deletedVectorUUIDs: Set<String>) async throws
    func recoverPendingOperations() async throws
    func resetAllData() async throws

    func countNewPhotosSince(date: Date, in dateRange: DateRange, using photoLibrary: any PhotoLibraryProviding) async throws -> Int

    func totalPhotosIndexed() async throws -> Int
    func totalDuplicateGroupsFound() async throws -> Int
    func totalPhotosDeleted() async throws -> Int
}
