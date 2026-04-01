import Foundation

struct ReviewStats: Equatable, Sendable {
    let groupsReviewed: Int
    let photosToDelete: Int
    let photosToKeep: Int
}

@Observable
@MainActor
final class ReviewState {
    enum Status: Equatable {
        case empty
        case reviewing(currentIndex: Int, groups: [DuplicateGroup])
        case confirming(deletionIds: [String], stats: ReviewStats)
        case deleting
        case allReviewed(stats: ReviewStats)
        case failed(AppError)
    }

    enum Action {
        case didLoadGroups([DuplicateGroup])
        case didToggleKeep(PhotoReference)
        case didSkipGroup
        case didConfirmGroup
        case didConfirmDeletion
        case didStartDeletion
        case didFinishDeletion(stats: ReviewStats)
        case didFail(AppError)
    }

    private(set) var status: Status = .empty
    private(set) var keepSelections: [String: Set<String>] = [:]

    var currentGroup: DuplicateGroup? {
        switch status {
        case .reviewing(let index, let groups) where index < groups.count:
            groups[index]
        default:
            nil
        }
    }

    func keptIds(for group: DuplicateGroup) -> Set<String> {
        keepSelections[group.id] ?? [group.bestCandidate.id]
    }

    func reduce(_ action: Action) {
        switch action {
        case .didLoadGroups(let groups):
            guard !groups.isEmpty else {
                status = .empty
                return
            }
            keepSelections = [:]
            status = .reviewing(currentIndex: 0, groups: groups)

        case .didToggleKeep(let photo):
            guard case .reviewing = status,
                  let group = currentGroup else { return }
            var kept = keptIds(for: group)
            switch kept.contains(photo.id) {
            case true:
                guard kept.count > 1 else { return }
                kept.remove(photo.id)
            case false:
                kept.insert(photo.id)
            }
            keepSelections[group.id] = kept

        case .didConfirmGroup:
            guard case .reviewing(let index, let groups) = status else { return }
            advanceToNext(index: index, groups: groups)

        case .didSkipGroup:
            guard case .reviewing(let index, let groups) = status else { return }
            keepSelections.removeValue(forKey: groups[index].id)
            advanceToNext(index: index, groups: groups)

        case .didConfirmDeletion:
            guard case .reviewing(_, let groups) = status else { return }
            let ids = buildDeletionIds(groups: groups)
            let stats = buildStats(groups: groups, deletionCount: ids.count)
            guard !ids.isEmpty else {
                status = .allReviewed(stats: stats)
                return
            }
            status = .confirming(deletionIds: ids, stats: stats)

        case .didStartDeletion:
            guard case .confirming = status else { return }
            status = .deleting

        case .didFinishDeletion(let stats):
            status = .allReviewed(stats: stats)

        case .didFail(let error):
            status = .failed(error)
        }
    }

    private func advanceToNext(index: Int, groups: [DuplicateGroup]) {
        let next = index + 1
        guard next < groups.count else {
            let ids = buildDeletionIds(groups: groups)
            let stats = buildStats(groups: groups, deletionCount: ids.count)
            guard !ids.isEmpty else {
                status = .allReviewed(stats: stats)
                return
            }
            status = .confirming(deletionIds: ids, stats: stats)
            return
        }
        status = .reviewing(currentIndex: next, groups: groups)
    }

    private func buildDeletionIds(groups: [DuplicateGroup]) -> [String] {
        var ids: [String] = []
        for group in groups {
            guard let kept = keepSelections[group.id] else { continue }
            let toDelete = group.photos.filter { !kept.contains($0.id) }
            ids.append(contentsOf: toDelete.map(\.assetId))
        }
        return ids
    }

    private func buildStats(groups: [DuplicateGroup], deletionCount: Int) -> ReviewStats {
        let reviewedGroups = groups.filter { keepSelections[$0.id] != nil }
        let totalKept = reviewedGroups.reduce(0) { $0 + (keepSelections[$1.id]?.count ?? 0) }
        return ReviewStats(
            groupsReviewed: reviewedGroups.count,
            photosToDelete: deletionCount,
            photosToKeep: totalKept
        )
    }
}
