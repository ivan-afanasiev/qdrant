import SwiftUI

struct ScanView: View {
    @Environment(\.dependencies) private var dependencies
    @State private var coordinator = ContinuousScanCoordinator()
    @State private var reviewState = ReviewState()
    @State private var fullscreenPhoto: PhotoReference?
    @State private var dragOffset: CGFloat = 0
    @State private var swipeDirection: SwipeDirection = .none

    let dateRange: DateRange
    let resumeSessionId: UUID?
    let onFinished: () -> Void

    init(dateRange: DateRange, resumeSessionId: UUID? = nil, onFinished: @escaping () -> Void) {
        self.dateRange = dateRange
        self.resumeSessionId = resumeSessionId
        self.onFinished = onFinished
    }

    var body: some View {
        VStack(spacing: 0) {
            switch coordinator.phase {
            case .idle:
                Spacer()
                idleView
                Spacer()

            case .scanning:
                scanningContent

            case .completed:
                completedContent

            case .failed(let error):
                Spacer()
                failedView(error: error)
                Spacer()

            case .cancelled:
                Spacer()
                cancelledView
                Spacer()
            }
        }
        .navigationTitle(L10n.scanning)
        .navigationBarBackButtonHidden(coordinator.isActive)
        .task {
            startPipeline()
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .onChange(of: coordinator.isActive) { _, active in
            UIApplication.shared.isIdleTimerDisabled = active
        }
        .onChange(of: coordinator.discoveredGroups) { _, groups in
            guard !groups.isEmpty else { return }
            reviewState.reduce(.didLoadGroups(groups))
        }
        .fullScreenCover(item: $fullscreenPhoto) { photo in
            FullscreenPhotoView(photo: photo) {
                fullscreenPhoto = nil
            }
        }
    }

    // MARK: - Idle

    private var idleView: some View {
        VStack(spacing: QSpacing.md) {
            ProgressView()
            Text(L10n.preparingToScan)
                .foregroundStyle(QColors.textTertiary)
        }
    }

    // MARK: - Scanning (with inline groups)

    private var scanningContent: some View {
        VStack(spacing: 0) {
            scanProgressBar
                .padding(.horizontal)
                .padding(.top, QSpacing.sm)

            switch reviewState.status {
            case .reviewing:
                reviewingSection
            case .allReviewed:
                waitingForMoreGroups
            default:
                scanningPlaceholder
            }
        }
    }

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

            Button(role: .destructive) {
                coordinator.cancel()
            } label: {
                Text(L10n.cancel)
                    .font(QTypography.caption)
            }
            .buttonStyle(.borderless)
        }
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

    private var waitingForMoreGroups: some View {
        VStack(spacing: QSpacing.lg) {
            Spacer()
            ProgressView()
            Text(L10n.waitingForMoreGroups)
                .font(QTypography.bodyMedium)
                .foregroundStyle(QColors.textTertiary)
            Spacer()
        }
    }

    // MARK: - Completed

    private var completedContent: some View {
        Group {
            switch reviewState.status {
            case .empty:
                completedEmptyView
            case .reviewing:
                VStack(spacing: 0) {
                    completedBadge
                        .padding(.horizontal)
                        .padding(.top, QSpacing.sm)
                    reviewingSection
                }
            case .deletingGroup:
                deletingView
            case .allReviewed:
                allReviewedView
            case .failed(let error):
                reviewFailedView(error: error)
            }
        }
    }

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

            Button(L10n.done) {
                onFinished()
            }
            .buttonStyle(.qPrimary)
            Spacer()
        }
    }

    // MARK: - Review Section (shared between scanning and completed)

    private var reviewingSection: some View {
        VStack(spacing: QSpacing.md) {
            headerBar
                .padding(.top, QSpacing.sm)

            ProgressView(value: Double(reviewState.currentIndex), total: Double(reviewState.totalGroups))
                .tint(QColors.primary)
                .padding(.horizontal)

            swipeableCardStack

            confirmGroupButton

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
            Text(L10n.groupNofTotal(reviewState.currentIndex + 1, reviewState.totalGroups))
                .font(QTypography.bodyLarge)
            Spacer()
            Button(L10n.skip) {
                animateSkip()
            }
            .buttonStyle(.qGhost)
        }
        .padding(.horizontal)
    }

    // MARK: - Swipeable Card Stack

    private var swipeableCardStack: some View {
        GeometryReader { geo in
            ZStack {
                if let group = reviewState.currentGroup {
                    GroupComparisonView(
                        group: group,
                        keptIds: reviewState.keptIds(for: group),
                        onToggleKeep: { photo in
                            withAnimation(QAnimation.springDefault) {
                                reviewState.reduce(.didToggleKeep(photo))
                            }
                        },
                        onFullscreen: { photo in
                            fullscreenPhoto = photo
                        }
                    )
                    .id(reviewState.currentIndex)
                    .offset(x: dragOffset)
                    .rotationEffect(.degrees(Double(dragOffset) / 30), anchor: .bottom)
                    .opacity(swipeOpacity)
                    .allowsHitTesting(!isDragging)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
                }
            }
            .overlay {
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(swipeGesture(screenWidth: geo.size.width))
                    .allowsHitTesting(isDragging)
            }
            .simultaneousGesture(swipeDetectionGesture(screenWidth: geo.size.width))
            .animation(QAnimation.springDefault, value: reviewState.currentIndex)
        }
    }

    private var swipeOpacity: Double {
        let progress = abs(dragOffset) / 200
        return Double(1 - progress * 0.3)
    }

    private var isDragging: Bool {
        dragOffset != 0
    }

    private func swipeDetectionGesture(screenWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { value in
                let horizontal = abs(value.translation.width)
                let vertical = abs(value.translation.height)
                guard horizontal > vertical else { return }
                dragOffset = value.translation.width
            }
            .onEnded { value in
                guard dragOffset != 0 else { return }
                let swipeThreshold = screenWidth * 0.3
                let velocity = value.predictedEndTranslation.width

                switch true {
                case value.translation.width < -swipeThreshold || velocity < -500:
                    performSwipeOut(direction: .left, screenWidth: screenWidth)
                case value.translation.width > swipeThreshold || velocity > 500:
                    performSwipeOut(direction: .right, screenWidth: screenWidth)
                default:
                    withAnimation(QAnimation.springDefault) {
                        dragOffset = 0
                    }
                }
            }
    }

    private func swipeGesture(screenWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                dragOffset = value.translation.width
            }
            .onEnded { value in
                let swipeThreshold = screenWidth * 0.3
                let velocity = value.predictedEndTranslation.width

                switch true {
                case value.translation.width < -swipeThreshold || velocity < -500:
                    performSwipeOut(direction: .left, screenWidth: screenWidth)
                case value.translation.width > swipeThreshold || velocity > 500:
                    performSwipeOut(direction: .right, screenWidth: screenWidth)
                default:
                    withAnimation(QAnimation.springDefault) {
                        dragOffset = 0
                    }
                }
            }
    }

    private func performSwipeOut(direction: SwipeDirection, screenWidth: CGFloat) {
        let exitX: CGFloat = direction == .left ? -screenWidth * 1.5 : screenWidth * 1.5
        swipeDirection = direction

        withAnimation(.easeIn(duration: 0.25)) {
            dragOffset = exitX
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            dragOffset = 0
            swipeDirection = .none
            skipCurrentGroup()
        }
    }

    private func animateSkip() {
        guard reviewState.currentGroup != nil else { return }
        performSwipeOut(direction: .left, screenWidth: UIScreen.main.bounds.width)
    }

    // MARK: - Buttons

    @ViewBuilder
    private var confirmGroupButton: some View {
        if let group = reviewState.currentGroup {
            let kept = reviewState.keptIds(for: group)
            let deleteCount = group.photos.count - kept.count

            switch deleteCount > 0 {
            case true:
                Button {
                    deleteCurrentGroup()
                } label: {
                    Label(L10n.deleteNPhotos(deleteCount), systemImage: QIcons.delete)
                }
                .buttonStyle(.qDestructive)
                .padding(.horizontal)

            case false:
                Button {
                    animateSkip()
                } label: {
                    Text(L10n.skip)
                }
                .buttonStyle(.qGhost)
                .padding(.horizontal)
            }
        }
    }

    // MARK: - Status Views

    private var deletingView: some View {
        VStack(spacing: QSpacing.md) {
            Spacer()
            ProgressView()
            Text(L10n.deletingPhotos)
                .foregroundStyle(QColors.textTertiary)
            Spacer()
        }
    }

    private var allReviewedView: some View {
        VStack(spacing: QSpacing.lg) {
            Spacer()
            QStatusIcon(QIcons.successFill, size: QSize.iconXLarge, color: QColors.success)

            Text(L10n.allDone)
                .font(QTypography.titleMedium)

            VStack(spacing: QSpacing.xs) {
                statRow(label: L10n.groupsReviewed, value: "\(reviewState.stats.groupsReviewed)")
                statRow(label: L10n.photosCleaned, value: "\(reviewState.stats.photosDeleted)")
            }
            .padding()
            .background(QColors.surfaceSubtle)
            .clipShape(RoundedRectangle(cornerRadius: QRadius.md))

            Button(L10n.finish) {
                onFinished()
            }
            .buttonStyle(.qPrimary)
            Spacer()
        }
        .padding()
    }

    private func failedView(error: AppError) -> some View {
        VStack(spacing: QSpacing.md) {
            QStatusIcon(QIcons.warningFill, size: QSize.iconLarge, color: QColors.error)
            Text(L10n.scanFailed)
                .font(QTypography.titleMedium)
            Text(error.localizedDescription)
                .font(QTypography.bodyMedium)
                .foregroundStyle(QColors.textTertiary)
                .multilineTextAlignment(.center)

            Button(L10n.retry) {
                startPipeline()
            }
            .buttonStyle(.qPrimary)
        }
    }

    private func reviewFailedView(error: AppError) -> some View {
        VStack(spacing: QSpacing.md) {
            Spacer()
            QStatusIcon(QIcons.warningFill, size: QSize.iconLarge, color: QColors.error)
            Text(L10n.error)
                .font(QTypography.titleMedium)
            Text(error.localizedDescription)
                .font(QTypography.bodyMedium)
                .foregroundStyle(QColors.textTertiary)
                .multilineTextAlignment(.center)

            Button(L10n.done) {
                onFinished()
            }
            .buttonStyle(.qPrimary)
            Spacer()
        }
        .padding()
    }

    private var cancelledView: some View {
        VStack(spacing: QSpacing.md) {
            QStatusIcon(QIcons.cancelFill, size: QSize.iconLarge, color: QColors.warning)
            Text(L10n.scanCancelled)
                .font(QTypography.titleMedium)

            Button(L10n.retry) {
                startPipeline()
            }
            .buttonStyle(.qPrimary)
        }
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

    private func statRow(label: LocalizedStringKey, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(QColors.textSecondary)
            Spacer()
            Text(value)
                .font(QTypography.numericMedium)
        }
    }

    // MARK: - Actions

    private func startPipeline() {
        guard !coordinator.isActive else { return }
        guard let deps = dependencies else { return }
        coordinator.startPipeline(
            dateRange: dateRange,
            resumeSessionId: resumeSessionId,
            deps: deps
        )
    }

    private func deleteCurrentGroup() {
        guard let deps = dependencies, let group = reviewState.currentGroup else { return }
        let idsToDelete = reviewState.deletionIdsForCurrentGroup()
        let keptIds = reviewState.keptIds(for: group)
        let keptCount = keptIds.count

        reviewState.reduce(.didConfirmGroup)

        guard !idsToDelete.isEmpty else {
            reviewState.reduce(.didFinishGroupDeletion(deleted: 0, kept: keptCount))
            persistGroupStatus(group: group, keptIds: keptIds, deletedAssetIds: [], deps: deps)
            return
        }

        Task {
            do {
                try await deps.photoLibrary.deleteAssets(idsToDelete)
                let uuids = idsToDelete.map { deterministicUUID(from: $0) }
                try await deps.vectorStore.delete(ids: uuids)
                reviewState.reduce(.didFinishGroupDeletion(deleted: idsToDelete.count, kept: keptCount))
                persistGroupStatus(group: group, keptIds: keptIds, deletedAssetIds: idsToDelete, deps: deps)
            } catch let error as AppError {
                reviewState.reduce(.didFail(error))
            } catch {
                reviewState.reduce(.didFail(.unknown(error.localizedDescription)))
            }
        }
    }

    private func persistGroupStatus(group: DuplicateGroup, keptIds: Set<String>, deletedAssetIds: [String], deps: Dependencies) {
        guard let groupUUID = UUID(uuidString: group.id) else { return }
        Task {
            if deletedAssetIds.isEmpty {
                try? await deps.scanStore.markGroupReviewed(groupId: groupUUID, keptVectorUUIDs: keptIds)
            } else {
                let deletedUUIDs = Set(deletedAssetIds.map { deterministicUUID(from: $0) })
                try? await deps.scanStore.markGroupDeleted(groupId: groupUUID, keptVectorUUIDs: keptIds, deletedVectorUUIDs: deletedUUIDs)
            }
        }
    }

    private func skipCurrentGroup() {
        guard let deps = dependencies, let group = reviewState.currentGroup else { return }
        let allIds = Set(group.photos.map(\.id))
        reviewState.reduce(.didSkipGroup)
        guard let groupUUID = UUID(uuidString: group.id) else { return }
        Task {
            try? await deps.scanStore.markGroupReviewed(groupId: groupUUID, keptVectorUUIDs: allIds)
        }
    }
}

// MARK: - Supporting Types

private enum SwipeDirection {
    case none, left, right
}
