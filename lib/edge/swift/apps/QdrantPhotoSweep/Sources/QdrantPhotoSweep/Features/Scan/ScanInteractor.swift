import SwiftUI

@Observable
@MainActor
final class ScanInteractor {

    enum Intent {
        case launched
        case scenePhaseChanged(ScenePhase)
        case cancelScan
        case skipGroup
        case deleteGroup
        case toggleKeep(PhotoReference)
        case switchViewMode(ViewMode)
        case groupReviewedFromGrid(UUID)
        case loadMoreGridPages
    }

    // MARK: - Owned State

    private(set) var coordinator = ContinuousScanCoordinator()
    private(set) var reviewState = ReviewState()
    private(set) var gridState = GroupGridState()
    private(set) var viewMode: ViewMode = .cards
    private(set) var hasLaunched = false
    private(set) var showCompletedBadge = false

    // MARK: - Derived

    var hasGroups: Bool {
        coordinator.groupsFoundCount > 0
            || !gridState.groups.isEmpty
            || reviewState.totalGroups > 0
    }

    var reviewGroupCounter: String {
        let reviewed = reviewState.reviewedInSession
        let total = max(reviewed + reviewState.pendingCount, coordinator.groupsFoundCount)
        return L10n.groupNofTotal(reviewed + 1, total)
    }

    var reviewProgressTotal: Double {
        let total = max(reviewState.totalGroups, coordinator.groupsFoundCount)
        return Double(total)
    }

    // MARK: - Dependencies (injected once)

    private var deps: Dependencies?

    private var scanUseCases: ScanFeature.UseCases? {
        guard let deps else { return nil }
        return ScanFeature.UseCases(
            loadInitialState: LoadInitialStateUseCase(
                scanStore: deps.scanStore,
                settings: deps.settings
            ),
            startScan: StartScanUseCase(coordinator: coordinator, deps: deps),
            cancelScan: CancelScanUseCase(coordinator: coordinator),
            manageBackground: ManageBackgroundExecutionUseCase(coordinator: coordinator)
        )
    }

    var reviewUseCases: ReviewFeature.UseCases? {
        deps?.reviewUseCases
    }

    var groupGridUseCases: GroupGridFeature.UseCases? {
        deps?.groupGridUseCases
    }

    // MARK: - Public API

    func configure(deps: Dependencies) {
        guard self.deps == nil else { return }
        self.deps = deps
        startObservationLoops()
    }

    func send(_ intent: Intent) {
        switch intent {
        case .launched:
            Task { await autoDetectAndLaunch() }
        case .scenePhaseChanged(let phase):
            handleScenePhaseChange(phase)
        case .cancelScan:
            Task { try? await scanUseCases?.cancelScan.execute(()) }
        case .skipGroup:
            skipCurrentGroup()
        case .deleteGroup:
            deleteCurrentGroup()
        case .toggleKeep(let photo):
            withAnimation(QAnimation.springDefault) {
                reviewState.reduce(.didToggleKeep(photo))
            }
        case .switchViewMode(let mode):
            withAnimation { viewMode = mode }
        case .groupReviewedFromGrid(let reviewedId):
            gridState.reduce(.didRemoveGroup(reviewedId))
            if reviewState.status == .noMoreGroups || reviewState.status == .idle {
                loadNextGroupFromDB()
            }
        case .loadMoreGridPages:
            loadMoreGridPages()
        }
    }

    // MARK: - Observation Loops

    private func startObservationLoops() {
        observeGroupsFoundCount()
        observeReviewLoading()
        observeCoordinatorPhase()
        observeCoordinatorActive()
        observeViewMode()
        observeRescanRequest()
    }

    private var lastSeenGroupsFoundCount: Int = 0
    private var lastSeenIsLoading: Bool = false
    private var lastSeenPhase: ContinuousScanCoordinator.Phase = .idle
    private var lastSeenIsActive: Bool = false
    private var lastSeenViewModeRaw: String = ViewMode.cards.rawValue
    private var lastSeenRescanId: UUID = UUID()

    private func observeGroupsFoundCount() {
        withObservationTracking {
            _ = coordinator.groupsFoundCount
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let count = self.coordinator.groupsFoundCount
                if count != self.lastSeenGroupsFoundCount {
                    self.lastSeenGroupsFoundCount = count
                    self.handleGroupsFound(count)
                }
                self.observeGroupsFoundCount()
            }
        }
    }

    private func observeReviewLoading() {
        withObservationTracking {
            _ = reviewState.isLoading
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let loading = self.reviewState.isLoading
                if loading != self.lastSeenIsLoading {
                    self.lastSeenIsLoading = loading
                    if loading { self.loadNextGroupFromDB() }
                }
                self.observeReviewLoading()
            }
        }
    }

    private func observeCoordinatorPhase() {
        withObservationTracking {
            _ = coordinator.phase
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let newPhase = self.coordinator.phase
                if newPhase != self.lastSeenPhase {
                    self.lastSeenPhase = newPhase
                    self.handlePhaseChange(newPhase)
                }
                self.observeCoordinatorPhase()
            }
        }
    }

    private func observeCoordinatorActive() {
        withObservationTracking {
            _ = coordinator.isActive
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let active = self.coordinator.isActive
                if active != self.lastSeenIsActive {
                    self.lastSeenIsActive = active
                    UIApplication.shared.isIdleTimerDisabled = active
                }
                self.observeCoordinatorActive()
            }
        }
    }

    private func observeViewMode() {
        withObservationTracking {
            _ = viewMode
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let raw = self.viewMode.rawValue
                if raw != self.lastSeenViewModeRaw {
                    self.lastSeenViewModeRaw = raw
                    if self.viewMode == .grid, self.gridState.status == .idle {
                        self.reloadGrid()
                    }
                }
                self.observeViewMode()
            }
        }
    }

    private func observeRescanRequest() {
        guard let deps else { return }
        lastSeenRescanId = deps.settings.rescanRequestId
        withObservationTracking {
            _ = deps.settings.rescanRequestId
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, let deps = self.deps else { return }
                let newId = deps.settings.rescanRequestId
                if newId != self.lastSeenRescanId {
                    self.lastSeenRescanId = newId
                    self.startRescan()
                }
                self.observeRescanRequest()
            }
        }
    }

    // MARK: - Auto Detect & Launch

    private func autoDetectAndLaunch() async {
        guard let scanUseCases else { return }
        do {
            let action = try await scanUseCases.loadInitialState.execute(())
            hasLaunched = true

            switch action {
            case .resumeScan(let dateRange, let sessionId):
                try? await scanUseCases.startScan.execute(
                    StartScanInput(dateRange: dateRange, resumeSessionId: sessionId)
                )
            case .reviewPending:
                loadNextGroupFromDB()
            case .startNewScan(let dateRange):
                try? await scanUseCases.startScan.execute(
                    StartScanInput(dateRange: dateRange, resumeSessionId: nil)
                )
            }
        } catch {
            hasLaunched = true
            AppLog.scan.error("Failed to load initial state: \(error)")
        }
    }

    // MARK: - Event Reactions

    private func handleScenePhaseChange(_ newPhase: ScenePhase) {
        switch newPhase {
        case .background where coordinator.isActive:
            Task { try? await scanUseCases?.manageBackground.execute(()) }
        case .active:
            coordinator.endExtendedBackgroundExecution()
            coordinator.resumeIfInterrupted()
        default:
            break
        }
    }

    private func handleGroupsFound(_ count: Int) {
        guard count > 0,
              reviewState.status == .idle || reviewState.status == .noMoreGroups
        else { return }
        loadNextGroupFromDB()
        if viewMode == .grid { reloadGrid() }
    }

    private func handlePhaseChange(_ newPhase: ContinuousScanCoordinator.Phase) {
        switch newPhase {
        case .completed:
            withAnimation { showCompletedBadge = true }
            Task {
                try? await Task.sleep(for: .seconds(3))
                withAnimation { showCompletedBadge = false }
            }
            if reviewState.status == .idle || reviewState.status == .noMoreGroups {
                loadNextGroupFromDB()
            }
            if viewMode == .grid { reloadGrid() }
        default:
            break
        }
    }

    // MARK: - Use Case Calls

    private func loadNextGroupFromDB() {
        guard let reviewUseCases else { return }
        Task {
            reviewState.reduce(.didStartLoading)
            do {
                let output = try await reviewUseCases.loadNextGroup.execute(())
                guard let group = output.group else {
                    reviewState.reduce(.didLoadEmpty)
                    return
                }
                reviewState.reduce(.didLoadGroup(group, pendingCount: output.pendingCount))
            } catch {
                reviewState.reduce(.didFail(error as? AppError ?? .unknown(error.localizedDescription)))
            }
        }
    }

    private func deleteCurrentGroup() {
        guard let reviewUseCases, let group = reviewState.currentGroup else { return }
        let keptIds = reviewState.keptIds(for: group)
        reviewState.reduce(.didConfirmGroup)

        Task {
            do {
                let result = try await reviewUseCases.deleteGroup.execute(
                    DeleteGroupInput(group: group, keptIds: keptIds)
                )
                reviewState.reduce(.didFinishGroupDeletion(deleted: result.deleted, kept: result.kept))
                if viewMode == .grid {
                    gridState.reduce(.didRemoveGroup(UUID(uuidString: group.id) ?? UUID()))
                }
            } catch {
                reviewState.reduce(.didFail(error as? AppError ?? .unknown(error.localizedDescription)))
            }
        }
    }

    private func skipCurrentGroup() {
        guard let reviewUseCases, let group = reviewState.currentGroup else { return }
        reviewState.reduce(.didSkipGroup)
        Task {
            try? await reviewUseCases.skipGroup.execute(SkipGroupInput(group: group))
        }
    }

    private func reloadGrid() {
        guard let groupGridUseCases else { return }
        gridState.reduce(.didStartLoading)
        Task {
            do {
                let output = try await groupGridUseCases.loadPage.execute(
                    GroupsPageInput(offset: 0, limit: GroupGridFeature.pageSize)
                )
                gridState.reduce(.didLoadPage(output, isFirstPage: true))
            } catch {
                gridState.reduce(.didFail(error as? AppError ?? .unknown(error.localizedDescription)))
            }
        }
    }

    private func startRescan() {
        guard let scanUseCases, let settings = deps?.settings else { return }
        Task {
            try? await scanUseCases.cancelScan.execute(())
            reviewState = ReviewState()
            gridState = GroupGridState()
            try? await scanUseCases.startScan.execute(
                StartScanInput(dateRange: settings.currentDateRange, resumeSessionId: nil)
            )
        }
    }

    private func loadMoreGridPages() {
        guard let groupGridUseCases, gridState.status != .loading else { return }
        gridState.reduce(.didStartLoading)
        Task {
            do {
                let output = try await groupGridUseCases.loadPage.execute(
                    GroupsPageInput(offset: gridState.currentOffset, limit: GroupGridFeature.pageSize)
                )
                gridState.reduce(.didLoadPage(output, isFirstPage: false))
            } catch {
                gridState.reduce(.didFail(error as? AppError ?? .unknown(error.localizedDescription)))
            }
        }
    }

    // MARK: - Cleanup

    func teardown() {
        UIApplication.shared.isIdleTimerDisabled = false
    }
}
