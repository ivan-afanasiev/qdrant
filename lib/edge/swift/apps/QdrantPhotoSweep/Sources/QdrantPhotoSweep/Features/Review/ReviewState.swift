import Foundation

struct ReviewStats: Equatable, Sendable {
    let groupsReviewed: Int
    let photosToDelete: Int
    let photosToKeep: Int
}

@Observable
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
        case didSelectKeep(PhotoReference)
        case didSkipGroup
        case didConfirmDeletion
        case didFinishDeletion(stats: ReviewStats)
        case didFail(AppError)
    }

    var status: Status = .empty
    var keepSelections: [String: String] = [:]
    var deletionCandidates: [String] = []

    var currentGroup: DuplicateGroup? {
        switch status {
        case .reviewing(let index, let groups) where index < groups.count:
            groups[index]
        default:
            nil
        }
    }

    func reduce(_ action: Action) {
        switch action {
        case .didLoadGroups(let groups):
            guard !groups.isEmpty else {
                status = .empty
                return
            }
            keepSelections = [:]
            deletionCandidates = []
            status = .reviewing(currentIndex: 0, groups: groups)

        case .didSelectKeep(let photo):
            guard case .reviewing(let index, let groups) = status,
                  index < groups.count else { return }
            let group = groups[index]
            keepSelections[group.id] = photo.id
            let toDelete = group.photos.filter { $0.id != photo.id }.map(\.assetId)
            deletionCandidates.append(contentsOf: toDelete)
            advanceToNext(index: index, groups: groups)

        case .didSkipGroup:
            guard case .reviewing(let index, let groups) = status else { return }
            advanceToNext(index: index, groups: groups)

        case .didConfirmDeletion:
            let stats = currentStats
            status = .confirming(deletionIds: deletionCandidates, stats: stats)

        case .didFinishDeletion(let stats):
            status = .allReviewed(stats: stats)

        case .didFail(let error):
            status = .failed(error)
        }
    }

    private func advanceToNext(index: Int, groups: [DuplicateGroup]) {
        let next = index + 1
        guard next < groups.count else {
            let stats = currentStats
            guard !deletionCandidates.isEmpty else {
                status = .allReviewed(stats: stats)
                return
            }
            status = .confirming(deletionIds: deletionCandidates, stats: stats)
            return
        }
        status = .reviewing(currentIndex: next, groups: groups)
    }

    private var currentStats: ReviewStats {
        ReviewStats(
            groupsReviewed: keepSelections.count,
            photosToDelete: deletionCandidates.count,
            photosToKeep: keepSelections.count
        )
    }
}
