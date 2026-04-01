import Foundation

struct ReviewStats: Equatable, Sendable {
    var groupsReviewed: Int
    var photosDeleted: Int
    var photosKept: Int
}

@Observable
@MainActor
final class ReviewState {
    enum Status: Equatable {
        case empty
        case reviewing
        case deletingGroup
        case allReviewed
        case failed(AppError)
    }

    enum Action {
        case didLoadGroups([DuplicateGroup])
        case didToggleKeep(PhotoReference)
        case didSkipGroup
        case didConfirmGroup
        case didFinishGroupDeletion(deleted: Int, kept: Int)
        case didFail(AppError)
    }

    private(set) var status: Status = .empty
    private(set) var keepSelections: [String: Set<String>] = [:]
    private(set) var stats = ReviewStats(groupsReviewed: 0, photosDeleted: 0, photosKept: 0)
    private(set) var groups: [DuplicateGroup] = []
    private(set) var currentIndex: Int = 0

    var currentGroup: DuplicateGroup? {
        guard case .reviewing = status, currentIndex < groups.count else { return nil }
        return groups[currentIndex]
    }

    var totalGroups: Int { groups.count }

    func keptIds(for group: DuplicateGroup) -> Set<String> {
        keepSelections[group.id] ?? [group.bestCandidate.id]
    }

    func deletionIdsForCurrentGroup() -> [String] {
        guard let group = currentGroup else { return [] }
        let kept = keptIds(for: group)
        return group.photos
            .filter { !kept.contains($0.id) }
            .map(\.assetId)
    }

    func reduce(_ action: Action) {
        switch action {
        case .didLoadGroups(let loadedGroups):
            guard !loadedGroups.isEmpty else {
                status = .empty
                return
            }
            groups = loadedGroups
            currentIndex = 0
            keepSelections = [:]
            stats = ReviewStats(groupsReviewed: 0, photosDeleted: 0, photosKept: 0)
            status = .reviewing

        case .didToggleKeep(let photo):
            guard case .reviewing = status, let group = currentGroup else { return }
            var kept = keptIds(for: group)
            switch kept.contains(photo.id) {
            case true:
                kept.remove(photo.id)
            case false:
                kept.insert(photo.id)
            }
            keepSelections[group.id] = kept

        case .didConfirmGroup:
            guard case .reviewing = status else { return }
            status = .deletingGroup

        case .didSkipGroup:
            guard case .reviewing = status else { return }
            let group = groups[currentIndex]
            keepSelections.removeValue(forKey: group.id)
            stats.groupsReviewed += 1
            advanceToNext()

        case .didFinishGroupDeletion(let deleted, let kept):
            guard case .deletingGroup = status else { return }
            stats.groupsReviewed += 1
            stats.photosDeleted += deleted
            stats.photosKept += kept
            advanceToNext()

        case .didFail(let error):
            status = .failed(error)
        }
    }

    private func advanceToNext() {
        let next = currentIndex + 1
        guard next < groups.count else {
            status = .allReviewed
            return
        }
        currentIndex = next
        status = .reviewing
    }
}
