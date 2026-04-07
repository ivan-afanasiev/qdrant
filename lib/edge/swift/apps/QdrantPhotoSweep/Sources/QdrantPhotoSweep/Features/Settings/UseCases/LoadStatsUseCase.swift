import Foundation

struct ScanStats: Equatable, Sendable {
    var totalPhotosIndexed: Int = 0
    var lastScanDate: Date?
    var duplicateGroupsFound: Int = 0
    var photosDeleted: Int = 0
}

struct LoadStatsUseCase: UseCase {
    let scanStore: any ScanSessionStoring

    func execute(_ input: Void) async throws -> ScanStats {
        let indexed = try await scanStore.totalPhotosIndexed()
        let groups = try await scanStore.totalDuplicateGroupsFound()
        let deleted = try await scanStore.totalPhotosDeleted()
        let lastCompleted = try await scanStore.latestCompletedSession()

        return ScanStats(
            totalPhotosIndexed: indexed,
            lastScanDate: lastCompleted?.scannedAt,
            duplicateGroupsFound: groups,
            photosDeleted: deleted
        )
    }
}
