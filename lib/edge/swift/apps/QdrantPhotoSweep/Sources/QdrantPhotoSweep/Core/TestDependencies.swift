#if DEBUG
import CoreGraphics
import Foundation

// MARK: - Test Dependencies Container

final class TestDependencies: DependencyProviding {
    let vectorStore: any VectorStoring
    let embeddingService: any EmbeddingProviding
    let photoLibrary: any PhotoLibraryProviding
    let scanStore: any ScanSessionStoring
    let settings: AppSettings

    init(
        vectorStore: any VectorStoring = MockVectorStore(),
        embeddingService: any EmbeddingProviding = MockEmbeddingService(),
        photoLibrary: any PhotoLibraryProviding = MockPhotoLibrary(),
        scanStore: any ScanSessionStoring = MockScanStore(),
        settings: AppSettings = AppSettings()
    ) {
        self.vectorStore = vectorStore
        self.embeddingService = embeddingService
        self.photoLibrary = photoLibrary
        self.scanStore = scanStore
        self.settings = settings
    }
}

// MARK: - Mock VectorStoring

final class MockVectorStore: VectorStoring, @unchecked Sendable {
    var existsResult: Bool = false
    var searchResults: [ScoredResult] = []
    var countResult: Int = 0

    func exists(id: String) async throws(AppError) -> Bool { existsResult }
    func upsert(points: [VectorPoint]) async throws(AppError) {}
    func search(vector: [Float], limit: Int, threshold: Float) async throws(AppError) -> [ScoredResult] { searchResults }
    func scroll(offset: String?, limit: Int) async throws(AppError) -> ScrollPage { ScrollPage(records: [], nextOffset: nil) }
    func delete(ids: [String]) async throws(AppError) {}
    func count() async throws(AppError) -> Int { countResult }
    func reset() async throws(AppError) {}
    func close() async {}
}

// MARK: - Mock EmbeddingProviding

final class MockEmbeddingService: EmbeddingProviding, @unchecked Sendable {
    var embeddingResult: [Float] = Array(repeating: 0, count: 768)

    func embed(image: CGImage) async throws(AppError) -> [Float] { embeddingResult }
}

// MARK: - Mock PhotoLibraryProviding

final class MockPhotoLibrary: PhotoLibraryProviding, @unchecked Sendable {
    var assets: [PhotoAsset] = []

    func requestAuthorization() async throws(AppError) {}
    func fetchAssets(in dateRange: DateRange) async throws(AppError) -> [PhotoAsset] { assets }
    func countAssets(in dateRange: DateRange) async throws(AppError) -> Int { assets.count }
    func loadThumbnail(for asset: PhotoAsset, size: CGSize) async throws(AppError) -> CGImage {
        throw .photoLibrary("Mock: no image available")
    }
    func loadFullImage(for asset: PhotoAsset) async throws(AppError) -> CGImage {
        throw .photoLibrary("Mock: no image available")
    }
    func deleteAssets(_ identifiers: [String]) async throws(AppError) {}
}

// MARK: - Mock ScanSessionStoring

final class MockScanStore: ScanSessionStoring, @unchecked Sendable {
    var sessions: [ScanSessionDTO] = []
    var groups: [DuplicateGroupDTO] = []

    func createSession(rangeStart: Date, rangeEnd: Date, totalPhotos: Int) async throws -> UUID { UUID() }
    func loadSession(id: UUID) async throws -> ScanSessionDTO? { sessions.first { $0.id == id } }
    func updateSessionStatus(_ sessionId: UUID, status: ScanSessionStatus, indexedPhotos: Int?) async throws {}
    func latestCompletedSession() async throws -> ScanSessionDTO? { sessions.first }
    func latestInterruptedSession() async throws -> ScanSessionDTO? { nil }
    func interruptActiveSessions() async throws {}
    func claimSessionLease(sessionId: UUID, owner: String, until: Date) async throws -> Bool { true }

    func persistScanBatch(
        sessionId: UUID,
        photos: [ScanPhotoRecord],
        similarityEdges: [SimilarityEdgeRecord]
    ) async throws -> PersistScanBatchResult {
        PersistScanBatchResult(groups: [])
    }

    func loadPendingGroups() async throws -> [DuplicateGroupDTO] { groups }
    func loadPendingGroupsPage(offset: Int, limit: Int) async throws -> [DuplicateGroupDTO] {
        Array(groups.dropFirst(offset).prefix(limit))
    }
    func loadPendingGroup(id: UUID) async throws -> DuplicateGroupDTO? { groups.first { $0.id == id } }
    func loadNextPendingGroup() async throws -> DuplicateGroupDTO? { groups.first }
    func pendingGroupCount() async throws -> Int { groups.count }
    func markGroupReviewed(groupId: UUID, keptVectorUUIDs: Set<String>) async throws {}
    func markGroupDeletionPending(groupId: UUID, keptVectorUUIDs: Set<String>, deletedVectorUUIDs: Set<String>) async throws {}
    func markGroupDeletionFailed(groupId: UUID, reason: String, deletedVectorUUIDs: Set<String>) async throws {}
    func markGroupDeleted(groupId: UUID, keptVectorUUIDs: Set<String>, deletedVectorUUIDs: Set<String>) async throws {}
    func recoverPendingOperations() async throws {}
    func resetAllData() async throws {}

    func countNewPhotosSince(date: Date, in dateRange: DateRange, using photoLibrary: any PhotoLibraryProviding) async throws -> Int { 0 }

    func totalPhotosIndexed() async throws -> Int { 0 }
    func totalDuplicateGroupsFound() async throws -> Int { 0 }
    func totalPhotosDeleted() async throws -> Int { 0 }
}
#endif
