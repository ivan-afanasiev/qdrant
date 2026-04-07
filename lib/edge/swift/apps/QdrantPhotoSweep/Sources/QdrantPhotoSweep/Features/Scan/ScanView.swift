import SwiftUI

enum ViewMode: String, CaseIterable {
    case cards
    case grid
}

struct ScanView: View {
    @Environment(\.dependencies) private var dependencies
    @Environment(\.scenePhase) private var scenePhase
    @State private var coordinator = ContinuousScanCoordinator()
    @State private var reviewState = ReviewState()
    @State private var gridState = GroupGridState()
    @State private var fullscreenPhoto: PhotoReference?
    @State private var dragOffset: CGFloat = 0
    @State private var showCompletedBadge = false
    @State private var viewMode: ViewMode = .cards
    @State private var hasLaunched = false

    private var reviewUseCases: ReviewFeature.UseCases? {
        dependencies?.reviewUseCases
    }

    private var scanUseCases: ScanFeature.UseCases? {
        guard let dependencies else { return nil }
        return ScanFeature.UseCases(
            loadInitialState: LoadInitialStateUseCase(
                scanStore: dependencies.scanStore,
                settings: dependencies.settings
            ),
            startScan: StartScanUseCase(coordinator: coordinator, deps: dependencies),
            cancelScan: CancelScanUseCase(coordinator: coordinator),
            manageBackground: ManageBackgroundExecutionUseCase(coordinator: coordinator)
        )
    }

    private var groupGridUseCases: GroupGridFeature.UseCases? {
        dependencies?.groupGridUseCases
    }

    private var hasGroups: Bool {
        coordinator.groupsFoundCount > 0 || !gridState.groups.isEmpty || reviewState.totalGroups > 0
    }

    var body: some View {
        content
            .navigationTitle(L10n.appTitle)
            .toolbar { toolbarContent }
            .task { await autoDetectAndLaunch() }
            .modifier(ScanEventHandlers(
                coordinator: coordinator,
                reviewState: reviewState,
                gridState: gridState,
                viewMode: $viewMode,
                showCompletedBadge: $showCompletedBadge,
                fullscreenPhoto: $fullscreenPhoto,
                scanUseCases: scanUseCases,
                loadNextGroupFromDB: loadNextGroupFromDB,
                reloadGrid: reloadGrid,
                startRescan: startRescan
            ))
    }

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 0) {
            if case .idle = coordinator.phase, !hasLaunched {
                loadingView
            } else if case .idle = coordinator.phase, hasLaunched {
                if hasGroups {
                    activeContent
                } else {
                    noGroupsView
                }
            } else {
                activeContent
            }
        }
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: QSpacing.md) {
            Spacer()
            ProgressView()
            Text(L10n.preparingToScan)
                .foregroundStyle(QColors.textTertiary)
            Spacer()
        }
    }

    // MARK: - No Groups (idle after scan, nothing found)

    private var noGroupsView: some View {
        VStack(spacing: QSpacing.md) {
            Spacer()
            QStatusIcon(QIcons.sparkles, size: QSize.iconLarge, color: QColors.success)
            Text(L10n.noDuplicatesFound)
                .font(QTypography.titleMedium)
            Text(L10n.libraryLooksClean)
                .foregroundStyle(QColors.textTertiary)
            Spacer()
        }
    }

    // MARK: - Active Content (scanning / reviewing)

    private var activeContent: some View {
        VStack(spacing: 0) {
            statusBanner

            switch viewMode {
            case .cards:
                cardsContent
            case .grid:
                gridContent
            }
        }
    }

    @ViewBuilder
    private var statusBanner: some View {
        if coordinator.isActive {
            scanProgressBar
                .padding(.horizontal)
                .padding(.top, QSpacing.sm)
        } else if coordinator.isInterrupted {
            interruptedBanner
                .padding(.horizontal)
                .padding(.top, QSpacing.sm)
        } else if showCompletedBadge {
            completedBadge
                .padding(.horizontal)
                .padding(.top, QSpacing.sm)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if coordinator.isActive {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    Task { try? await scanUseCases?.cancelScan.execute(()) }
                } label: {
                    Text(L10n.cancel)
                        .font(QTypography.caption)
                }
                .buttonStyle(.borderless)
            }
        }

        if hasGroups {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    withAnimation { viewMode = viewMode == .cards ? .grid : .cards }
                } label: {
                    Image(systemName: viewMode == .cards ? QIcons.squareGrid : QIcons.rectangleStack)
                }
            }
        }
    }

    // MARK: - Cards Content (review mode)

    private var cardsContent: some View {
        Group {
            switch reviewState.status {
            case .reviewing:
                reviewingSection
            case .loading:
                ReviewLoadingView()
            case .deletingGroup:
                ReviewDeletingView()
            case .allReviewed:
                ReviewAllDoneView(stats: reviewState.stats, onFinished: {})
            case .failed(let error):
                ReviewFailedView(error: error, onDismiss: {})
            case .noMoreGroups, .idle:
                if case .completed = coordinator.phase {
                    completedEmptyView
                } else {
                    scanningPlaceholder
                }
            }
        }
    }

    // MARK: - Grid Content

    private var gridContent: some View {
        InlineGroupGridView(
            state: gridState,
            useCases: groupGridUseCases,
            reviewUseCases: reviewUseCases,
            onGroupReviewed: { reviewedId in
                gridState.reduce(.didRemoveGroup(reviewedId))
                if reviewState.status == .noMoreGroups || reviewState.status == .idle {
                    loadNextGroupFromDB()
                }
            }
        )
    }

    // MARK: - Progress Bar

    private var scanProgressBar: some View {
        VStack(spacing: QSpacing.xs) {
            ProgressView(value: coordinator.scanProgress)
                .tint(QColors.primary)

            HStack {
                if case .scanning(let processed, let total, let groupsFound) = coordinator.phase {
                    Text(L10n.scanProgressStatus(processed, total))
                        .font(QTypography.caption)
                        .foregroundStyle(QColors.textTertiary)
                    Spacer()
                    if groupsFound > 0 {
                        Text(L10n.groupsFoundSoFar(groupsFound))
                            .font(QTypography.caption)
                            .foregroundStyle(QColors.primary)
                    }
                }
            }
        }
    }

    private var interruptedBanner: some View {
        HStack(spacing: QSpacing.xs) {
            ProgressView()
                .controlSize(.small)
            Text(L10n.scanResuming)
                .font(QTypography.caption)
                .foregroundStyle(QColors.textSecondary)
            Spacer()
        }
        .padding(.vertical, QSpacing.xs)
    }

    private var scanningPlaceholder: some View {
        VStack(spacing: QSpacing.lg) {
            Spacer()
            progressRing(value: coordinator.scanProgress)

            Text(L10n.embeddingPhotos)
                .font(QTypography.bodyLarge)
            Text(L10n.scanningWithInlineDetection)
                .font(QTypography.bodyMedium)
                .foregroundStyle(QColors.textTertiary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding()
    }

    private func progressRing(value: Double) -> some View {
        ZStack {
            Circle()
                .stroke(lineWidth: QSize.progressStroke)
                .foregroundStyle(QColors.surfaceMuted)
            Circle()
                .trim(from: 0, to: value)
                .stroke(style: StrokeStyle(lineWidth: QSize.progressStroke, lineCap: .round))
                .foregroundStyle(QColors.primary)
                .rotationEffect(.degrees(-90))
                .animation(QAnimation.smooth, value: value)
            VStack {
                Text("\(Int(value * 100))%")
                    .font(QTypography.numericLarge)
            }
        }
        .frame(width: QSize.progressRing, height: QSize.progressRing)
    }

    // MARK: - Completed

    private var completedBadge: some View {
        HStack(spacing: QSpacing.xs) {
            Image(systemName: QIcons.successFill)
                .foregroundStyle(QColors.success)
            Text(L10n.scanComplete)
                .font(QTypography.caption)
                .foregroundStyle(QColors.textSecondary)
            Spacer()
        }
        .padding(.vertical, QSpacing.xs)
    }

    private var completedEmptyView: some View {
        VStack(spacing: QSpacing.md) {
            Spacer()
            QStatusIcon(QIcons.sparkles, size: QSize.iconLarge, color: QColors.success)
            Text(L10n.noDuplicatesFound)
                .font(QTypography.titleMedium)
            Text(L10n.libraryLooksClean)
                .foregroundStyle(QColors.textTertiary)
            Spacer()
        }
    }

    // MARK: - Review Section

    private var reviewGroupCounter: String {
        let reviewed = reviewState.reviewedInSession
        let total = max(reviewed + reviewState.pendingCount, coordinator.groupsFoundCount)
        return L10n.groupNofTotal(reviewed + 1, total)
    }

    private var reviewProgressTotal: Double {
        let total = max(reviewState.totalGroups, coordinator.groupsFoundCount)
        return Double(total)
    }

    private var reviewingSection: some View {
        VStack(spacing: QSpacing.md) {
            headerBar
                .padding(.top, QSpacing.sm)

            if reviewProgressTotal > 0 {
                ProgressView(value: Double(reviewState.reviewedInSession), total: reviewProgressTotal)
                    .tint(QColors.primary)
                    .padding(.horizontal)
            }

            ReviewCardStack(
                group: reviewState.currentGroup,
                keptIds: reviewState.currentGroup.map { reviewState.keptIds(for: $0) } ?? [],
                dragOffset: $dragOffset,
                fullscreenPhoto: $fullscreenPhoto,
                onToggleKeep: { photo in
                    withAnimation(QAnimation.springDefault) {
                        reviewState.reduce(.didToggleKeep(photo))
                    }
                },
                onSwipedOut: { skipCurrentGroup() }
            )

            ReviewConfirmButton(
                group: reviewState.currentGroup,
                keptIds: reviewState.currentGroup.map { reviewState.keptIds(for: $0) } ?? [],
                onDelete: { deleteCurrentGroup() },
                onSkip: { animateSkip() }
            )

            Text(L10n.tapToKeepHint)
                .font(QTypography.caption)
                .foregroundStyle(QColors.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
                .padding(.bottom, QSpacing.sm)
        }
    }

    private var headerBar: some View {
        HStack {
            Text(reviewGroupCounter)
                .font(QTypography.bodyLarge)
                .contentTransition(.numericText())
                .animation(.default, value: reviewGroupCounter)
            Spacer()
            Button(L10n.skip) {
                animateSkip()
            }
            .buttonStyle(.qGhost)
        }
        .padding(.horizontal)
    }

    // MARK: - Swipe Animation

    private func animateSkip() {
        guard reviewState.currentGroup != nil else { return }
        let screenWidth = UIScreen.main.bounds.width
        let exitX: CGFloat = -screenWidth * 1.5

        withAnimation(.easeIn(duration: 0.25)) {
            dragOffset = exitX
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            dragOffset = 0
            skipCurrentGroup()
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

    // MARK: - Actions (use case delegation)

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
        guard let scanUseCases, let settings = dependencies?.settings else { return }
        Task {
            try? await scanUseCases.cancelScan.execute(())
            reviewState = ReviewState()
            gridState = GroupGridState()
            try? await scanUseCases.startScan.execute(
                StartScanInput(dateRange: settings.currentDateRange, resumeSessionId: nil)
            )
        }
    }
}

// MARK: - Event Handlers (extracted to help the Swift type-checker)

private struct ScanEventHandlers: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dependencies) private var dependencies

    let coordinator: ContinuousScanCoordinator
    let reviewState: ReviewState
    let gridState: GroupGridState
    @Binding var viewMode: ViewMode
    @Binding var showCompletedBadge: Bool
    @Binding var fullscreenPhoto: PhotoReference?
    let scanUseCases: ScanFeature.UseCases?
    let loadNextGroupFromDB: () -> Void
    let reloadGrid: () -> Void
    let startRescan: () -> Void

    func body(content: Content) -> some View {
        content
            .onDisappear {
                UIApplication.shared.isIdleTimerDisabled = false
            }
            .onChange(of: coordinator.isActive) { _, active in
                UIApplication.shared.isIdleTimerDisabled = active
            }
            .onChange(of: scenePhase) { _, newPhase in
                handleScenePhaseChange(newPhase)
            }
            .onChange(of: coordinator.groupsFoundCount) { _, count in
                handleGroupsFound(count)
            }
            .onChange(of: reviewState.isLoading) { _, loading in
                if loading { loadNextGroupFromDB() }
            }
            .onChange(of: coordinator.phase) { _, newPhase in
                handlePhaseChange(newPhase)
            }
            .onChange(of: viewMode) { _, mode in
                if mode == .grid, gridState.status == .idle { reloadGrid() }
            }
            .onChange(of: dependencies?.settings.rescanRequestId) { _, _ in
                startRescan()
            }
            .fullScreenCover(item: $fullscreenPhoto) { photo in
                FullscreenPhotoView(photo: photo) {
                    fullscreenPhoto = nil
                }
            }
    }

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
}
