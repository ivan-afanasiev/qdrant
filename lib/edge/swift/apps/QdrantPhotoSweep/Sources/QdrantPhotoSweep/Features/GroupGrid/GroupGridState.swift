import Foundation

enum GroupGridFeature {
    struct UseCases: Sendable {
        let loadPage: LoadGroupsPageUseCase
        let loadGroup: LoadGroupByIdUseCase
    }

    static let pageSize = 20
}

@Observable
@MainActor
final class GroupGridState {
    enum Status: Equatable {
        case idle
        case loading
        case loaded
        case failed(AppError)
    }

    enum Action {
        case didStartLoading
        case didLoadPage(GroupsPageOutput, isFirstPage: Bool)
        case didFail(AppError)
        case didRemoveGroup(UUID)
    }

    private(set) var status: Status = .idle
    private(set) var groups: [GroupSummary] = []
    private(set) var totalCount: Int = 0
    private(set) var hasMore: Bool = false

    var currentOffset: Int { groups.count }

    func reduce(_ action: Action) {
        switch action {
        case .didStartLoading:
            if groups.isEmpty {
                status = .loading
            }

        case .didLoadPage(let output, let isFirstPage):
            if isFirstPage {
                groups = output.groups
            } else {
                groups.append(contentsOf: output.groups)
            }
            totalCount = output.totalCount
            hasMore = output.hasMore
            status = .loaded

        case .didFail(let error):
            status = .failed(error)

        case .didRemoveGroup(let id):
            groups.removeAll { $0.id == id }
            totalCount = max(totalCount - 1, 0)
        }
    }
}
