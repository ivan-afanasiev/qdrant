import SwiftUI

struct SwipeReviewView: View {
    @Environment(\.dependencies) private var dependencies
    @State private var reviewState = ReviewState()
    @State private var fullscreenPhoto: PhotoReference?
    @State private var dragOffset: CGFloat = 0
    @State private var swipeDirection: SwipeDirection = .none
    @State private var loaded = false

    let onFinished: () -> Void

    var body: some View {
        Group {
            switch loaded {
            case false:
                ProgressView()

            case true:
                reviewContent
            }
        }
        .navigationTitle(L10n.reviewDuplicates)
        .task {
            await loadFromPersistence()
        }
        .fullScreenCover(item: $fullscreenPhoto) { photo in
            FullscreenPhotoView(photo: photo) {
                fullscreenPhoto = nil
            }
        }
    }

    private func loadFromPersistence() async {
        guard let deps = dependencies else { return }

        if let pendingDTOs = try? await deps.scanStore.loadPendingGroups(), !pendingDTOs.isEmpty {
            let groups = pendingDTOs.compactMap { $0.toDuplicateGroup() }
            if !groups.isEmpty {
                reviewState.reduce(.didLoadGroups(groups))
            }
        }
        loaded = true
    }

    // MARK: - Review Phase

    @ViewBuilder
    private var reviewContent: some View {
        VStack {
            switch reviewState.status {
            case .empty:
                emptyView

            case .reviewing:
                reviewingView

            case .deletingGroup:
                deletingView

            case .allReviewed:
                allReviewedView

            case .failed(let error):
                failedView(error: error)
            }
        }
    }

    private var emptyView: some View {
        VStack(spacing: QSpacing.md) {
            QStatusIcon(QIcons.sparkles, size: QSize.iconLarge, color: QColors.success)
            Text(L10n.noDuplicatesFound)
                .font(QTypography.titleMedium)
            Text(L10n.libraryLooksClean)
                .foregroundStyle(QColors.textTertiary)

            Button(L10n.done) {
                onFinished()
            }
            .buttonStyle(.qPrimary)
        }
    }

    private var reviewingView: some View {
        VStack(spacing: QSpacing.md) {
            headerBar

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
            ProgressView()
            Text(L10n.deletingPhotos)
                .foregroundStyle(QColors.textTertiary)
        }
    }

    private var allReviewedView: some View {
        VStack(spacing: QSpacing.lg) {
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
        }
        .padding()
    }

    private func failedView(error: AppError) -> some View {
        VStack(spacing: QSpacing.md) {
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
        }
        .padding()
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

    // MARK: - Deletion

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
