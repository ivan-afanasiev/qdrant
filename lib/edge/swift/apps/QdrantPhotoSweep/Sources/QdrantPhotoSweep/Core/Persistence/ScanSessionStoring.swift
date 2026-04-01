import Foundation

protocol ScanSessionStoring: Sendable {
    func createSession(rangeStart: Date, rangeEnd: Date, totalPhotos: Int) async throws -> UUID
    func updateSessionStatus(_ sessionId: UUID, status: ScanSessionStatus, indexedPhotos: Int?) async throws
    func latestCompletedSession() async throws -> ScanSessionDTO?
    func latestInterruptedSession() async throws -> ScanSessionDTO?
    func interruptActiveSessions() async throws

    func recordIndexedPhoto(sessionId: UUID, assetLocalId: String, vectorUUID: String, dimensions: Int) async throws

    func saveDuplicateGroups(_ groups: [DuplicateGroup], sessionId: UUID) async throws
    func loadPendingGroups() async throws -> [DuplicateGroupDTO]
    func markGroupReviewed(groupId: UUID, keptVectorUUIDs: Set<String>) async throws
    func markGroupDeleted(groupId: UUID, keptVectorUUIDs: Set<String>, deletedVectorUUIDs: Set<String>) async throws
    func deleteAllPendingGroups() async throws

    func countNewPhotosSince(date: Date, in dateRange: DateRange, using photoLibrary: any PhotoLibraryProviding) async throws -> Int
}
