import Foundation

enum ReviewFeature {
    struct UseCases: Sendable {
        let deleteGroup: DeleteGroupUseCase
        let skipGroup: SkipGroupUseCase
        let loadNextGroup: LoadNextGroupUseCase
    }
}

struct ReviewStats: Equatable, Sendable {
    var groupsReviewed: Int
    var photosDeleted: Int
    var photosKept: Int
}

@Observable
@MainActor
final class ReviewState {
    enum Status: Equatable {
        case idle
        case loading
        case reviewing
        case deletingGroup
        case noMoreGroups
        case allReviewed
        case failed(AppError)
    }

    enum Action {
        case didStartLoading
        case didLoadGroup(DuplicateGroup, pendingCount: Int)
        case didLoadEmpty
        case didToggleKeep(PhotoReference)
        case didSkipGroup
        case didConfirmGroup
        case didFinishGroupDeletion(deleted: Int, kept: Int)
        case didFail(AppError)
    }

    private(set) var status: Status = .idle
    private(set) var keepSelections: [String: Set<String>] = [:]
    private(set) var stats = ReviewStats(groupsReviewed: 0, photosDeleted: 0, photosKept: 0)
    private(set) var currentGroup: DuplicateGroup?
    private(set) var pendingCount: Int = 0
    private(set) var reviewedInSession: Int = 0

    var totalGroups: Int { reviewedInSession + pendingCount }

    var isLoading: Bool { status == .loading }

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
        case .didStartLoading:
            status = .loading

        case .didLoadGroup(let group, let count):
            currentGroup = group
            pendingCount = count
            keepSelections = [group.id: [group.bestCandidate.id]]
            status = .reviewing

        case .didLoadEmpty:
            currentGroup = nil
            pendingCount = 0
            if reviewedInSession > 0 {
                status = .allReviewed
            } else {
                status = .noMoreGroups
            }

        case .didToggleKeep(let photo):
            guard case .reviewing = status, let group = currentGroup else { return }
            var kept = keptIds(for: group)
            if kept.contains(photo.id) {
                kept.remove(photo.id)
            } else {
                kept.insert(photo.id)
            }
            keepSelections[group.id] = kept

        case .didConfirmGroup:
            guard case .reviewing = status else { return }
            status = .deletingGroup

        case .didSkipGroup:
            guard case .reviewing = status else { return }
            reviewedInSession += 1
            stats.groupsReviewed += 1
            currentGroup = nil
            status = .loading

        case .didFinishGroupDeletion(let deleted, let kept):
            guard case .deletingGroup = status else { return }
            reviewedInSession += 1
            stats.groupsReviewed += 1
            stats.photosDeleted += deleted
            stats.photosKept += kept
            currentGroup = nil
            status = .loading

        case .didFail(let error):
            status = .failed(error)
        }
    }
}

extension Dependencies {
    var reviewUseCases: ReviewFeature.UseCases {
        ReviewFeature.UseCases(
            deleteGroup: DeleteGroupUseCase(
                photoLibrary: photoLibrary,
                vectorStore: vectorStore,
                scanStore: scanStore
            ),
            skipGroup: SkipGroupUseCase(scanStore: scanStore),
            loadNextGroup: LoadNextGroupUseCase(scanStore: scanStore)
        )
    }

    var groupGridUseCases: GroupGridFeature.UseCases {
        GroupGridFeature.UseCases(
            loadPage: LoadGroupsPageUseCase(scanStore: scanStore),
            loadGroup: LoadGroupByIdUseCase(scanStore: scanStore)
        )
    }
}
