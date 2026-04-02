import Foundation

@Observable
@MainActor
final class HomeState {
    struct Stats: Equatable {
        var totalPhotosIndexed: Int = 0
        var lastScanDate: Date?
        var duplicateGroupsFound: Int = 0
        var photosDeleted: Int = 0
    }

    enum Action {
        case didLoadStats(Stats)
        case didLoadBannerData(
            interruptedSession: ScanSessionDTO?,
            groupingInterruptedSession: ScanSessionDTO?,
            newPhotoCount: Int,
            lastSession: ScanSessionDTO?,
            pendingGroupCount: Int
        )
    }

    var stats = Stats()
    var interruptedSession: ScanSessionDTO?
    var groupingInterruptedSession: ScanSessionDTO?
    var newPhotoCount: Int = 0
    var lastSession: ScanSessionDTO?
    var pendingGroupCount: Int = 0

    func reduce(_ action: Action) {
        switch action {
        case .didLoadStats(let stats):
            self.stats = stats

        case .didLoadBannerData(let interrupted, let groupingInterrupted, let newCount, let last, let pending):
            interruptedSession = interrupted
            groupingInterruptedSession = groupingInterrupted
            newPhotoCount = newCount
            lastSession = last
            pendingGroupCount = pending
        }
    }

    func loadData(scanStore: any ScanSessionStoring, photoLibrary: any PhotoLibraryProviding) async {
        async let statsResult: Void = loadStats(scanStore: scanStore)
        async let bannerResult: Void = loadBannerData(scanStore: scanStore, photoLibrary: photoLibrary)
        _ = await (statsResult, bannerResult)
    }

    private func loadStats(scanStore: any ScanSessionStoring) async {
        do {
            let indexed = try await scanStore.totalPhotosIndexed()
            let groups = try await scanStore.totalDuplicateGroupsFound()
            let deleted = try await scanStore.totalPhotosDeleted()
            let lastCompleted = try await scanStore.latestCompletedSession()

            reduce(.didLoadStats(Stats(
                totalPhotosIndexed: indexed,
                lastScanDate: lastCompleted?.scannedAt,
                duplicateGroupsFound: groups,
                photosDeleted: deleted
            )))
        } catch {
            // Stats remain at zero defaults
        }
    }

    private func loadBannerData(scanStore: any ScanSessionStoring, photoLibrary: any PhotoLibraryProviding) async {
        do {
            let interrupted = try await scanStore.latestInterruptedSession()
            let groupingInterrupted = try await scanStore.latestGroupingInterruptedSession()
            var newCount = 0
            let lastCompleted = try await scanStore.latestCompletedSession()
            let pending = try await scanStore.loadPendingGroups()

            if let session = lastCompleted {
                let range = DateRange(start: session.rangeStart, end: session.rangeEnd)
                newCount = try await scanStore.countNewPhotosSince(
                    date: session.scannedAt,
                    in: range,
                    using: photoLibrary
                )
            }

            reduce(.didLoadBannerData(
                interruptedSession: interrupted,
                groupingInterruptedSession: groupingInterrupted,
                newPhotoCount: newCount,
                lastSession: lastCompleted,
                pendingGroupCount: pending.count
            ))
        } catch {
            // Banners remain hidden
        }
    }
}
