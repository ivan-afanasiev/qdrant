import Foundation
import os

struct LoadHomeDataOutput: Sendable {
    let stats: HomeState.Stats
    let interruptedSession: ScanSessionDTO?
    let newPhotoCount: Int
    let lastSession: ScanSessionDTO?
    let pendingGroupCount: Int
}

struct LoadHomeDataUseCase: UseCase {
    let scanStore: any ScanSessionStoring
    let photoLibrary: any PhotoLibraryProviding

    func execute(_ input: Void) async throws -> LoadHomeDataOutput {
        async let statsResult = loadStats()
        async let bannerResult = loadBannerData()
        let (stats, banner) = await (statsResult, bannerResult)
        return LoadHomeDataOutput(
            stats: stats,
            interruptedSession: banner.interrupted,
            newPhotoCount: banner.newCount,
            lastSession: banner.lastSession,
            pendingGroupCount: banner.pendingCount
        )
    }

    private func loadStats() async -> HomeState.Stats {
        do {
            let indexed = try await scanStore.totalPhotosIndexed()
            let groups = try await scanStore.totalDuplicateGroupsFound()
            let deleted = try await scanStore.totalPhotosDeleted()
            let lastCompleted = try await scanStore.latestCompletedSession()

            return HomeState.Stats(
                totalPhotosIndexed: indexed,
                lastScanDate: lastCompleted?.scannedAt,
                duplicateGroupsFound: groups,
                photosDeleted: deleted
            )
        } catch {
            AppLog.home.error("Failed to load stats: \(error)")
            return HomeState.Stats()
        }
    }

    private func loadBannerData() async -> (interrupted: ScanSessionDTO?, newCount: Int, lastSession: ScanSessionDTO?, pendingCount: Int) {
        do {
            let interrupted = try await scanStore.latestInterruptedSession()
            let lastCompleted = try await scanStore.latestCompletedSession()
            let pending = try await scanStore.loadPendingGroups()

            var newCount = 0
            if let session = lastCompleted {
                let range = DateRange(start: session.rangeStart, end: session.rangeEnd)
                newCount = try await scanStore.countNewPhotosSince(
                    date: session.scannedAt,
                    in: range,
                    using: photoLibrary
                )
            }

            return (interrupted, newCount, lastCompleted, pending.count)
        } catch {
            AppLog.home.error("Failed to load banner data: \(error)")
            return (nil, 0, nil, 0)
        }
    }
}
