import SwiftUI

struct SwipeReviewView: View {
    @Environment(\.dependencies) private var dependencies
    @State private var detectionState = DuplicateDetectionState()
    @State private var reviewState = ReviewState()
    @State private var fullscreenPhoto: PhotoReference?

    let threshold: Float
    let onFinished: () -> Void

    var body: some View {
        Group {
            switch detectionState.status {
            case .idle, .analyzing:
                analyzingView

            case .complete(let groups):
                reviewContent(groups: groups)

            case .failed(let error):
                detectionFailedView(error: error)
            }
        }
        .navigationTitle(L10n.reviewDuplicates)
        .task {
            await runDetection()
        }
        .fullScreenCover(item: $fullscreenPhoto) { photo in
            FullscreenPhotoView(photo: photo) {
                fullscreenPhoto = nil
            }
        }
    }

    // MARK: - Detection Phase

    private var analyzingView: some View {
        VStack(spacing: QSpacing.lg) {
            let progress = detectionProgress

            ZStack {
                Circle()
                    .stroke(lineWidth: QSize.progressStroke)
                    .foregroundStyle(QColors.surfaceMuted)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(style: StrokeStyle(lineWidth: QSize.progressStroke, lineCap: .round))
                    .foregroundStyle(QColors.primary)
                    .rotationEffect(.degrees(-90))
                    .animation(QAnimation.smooth, value: progress)
                VStack {
                    Text("\(Int(progress * 100))%")
                        .font(QTypography.numericLarge)
                }
            }
            .frame(width: QSize.progressRing, height: QSize.progressRing)

            Text(L10n.findingDuplicates)
                .font(QTypography.bodyLarge)
            Text(L10n.findingDuplicatesSubtitle)
                .font(QTypography.bodyMedium)
                .foregroundStyle(QColors.textTertiary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    private var detectionProgress: Double {
        switch detectionState.status {
        case .analyzing(let progress): progress
        default: 0
        }
    }

    private func detectionFailedView(error: AppError) -> some View {
        VStack(spacing: QSpacing.md) {
            QStatusIcon(QIcons.warningFill, size: QSize.iconLarge, color: QColors.error)
            Text(L10n.error)
                .font(QTypography.titleMedium)
            Text(error.localizedDescription)
                .font(QTypography.bodyMedium)
                .foregroundStyle(QColors.textTertiary)
                .multilineTextAlignment(.center)

            Button(L10n.retry) {
                Task { await runDetection() }
            }
            .buttonStyle(.qPrimary)

            Button(L10n.done) {
                onFinished()
            }
            .buttonStyle(.qGhost)
        }
        .padding()
    }

    private func runDetection() async {
        guard let deps = dependencies else { return }
        await detectionState.findDuplicates(
            vectorStore: deps.vectorStore,
            threshold: threshold
        )
        switch detectionState.status {
        case .complete(let groups):
            reviewState.reduce(.didLoadGroups(groups))
        default:
            break
        }
    }

    // MARK: - Review Phase

    @ViewBuilder
    private func reviewContent(groups: [DuplicateGroup]) -> some View {
        VStack {
            switch reviewState.status {
            case .empty:
                emptyView

            case .reviewing(let index, let allGroups):
                reviewingView(index: index, total: allGroups.count)

            case .confirming(let ids, let stats):
                confirmingView(deletionCount: ids.count, stats: stats)

            case .deleting:
                deletingView

            case .allReviewed(let stats):
                allReviewedView(stats: stats)

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

    private func reviewingView(index: Int, total: Int) -> some View {
        VStack(spacing: QSpacing.md) {
            HStack {
                Text(L10n.groupNofTotal(index + 1, total))
                    .font(QTypography.bodyLarge)
                Spacer()
                Button(L10n.skip) {
                    withAnimation {
                        reviewState.reduce(.didSkipGroup)
                    }
                }
                .buttonStyle(.qGhost)
            }
            .padding(.horizontal)

            ProgressView(value: Double(index), total: Double(total))
                .tint(QColors.primary)
                .padding(.horizontal)

            cardStack

            confirmGroupButton

            Text(L10n.tapToKeepHint)
                .font(QTypography.caption)
                .foregroundStyle(QColors.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
    }

    @ViewBuilder
    private var cardStack: some View {
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
        }
    }

    @ViewBuilder
    private var confirmGroupButton: some View {
        if let group = reviewState.currentGroup {
            let kept = reviewState.keptIds(for: group)
            let deleteCount = group.photos.count - kept.count

            switch deleteCount > 0 {
            case true:
                Button {
                    withAnimation {
                        reviewState.reduce(.didConfirmGroup)
                    }
                } label: {
                    Label(L10n.deleteNPhotos(deleteCount), systemImage: QIcons.delete)
                }
                .buttonStyle(.qDestructive)
                .padding(.horizontal)

            case false:
                Button {
                    withAnimation {
                        reviewState.reduce(.didConfirmGroup)
                    }
                } label: {
                    Text(L10n.skip)
                }
                .buttonStyle(.qGhost)
                .padding(.horizontal)
            }
        }
    }

    private func confirmingView(deletionCount: Int, stats: ReviewStats) -> some View {
        VStack(spacing: QSpacing.lg) {
            QStatusIcon(QIcons.trashCircle, size: QSize.iconLarge, color: QColors.warning)

            Text(L10n.readyToCleanUp)
                .font(QTypography.titleMedium)

            VStack(spacing: QSpacing.xs) {
                statRow(label: L10n.groupsReviewed, value: "\(stats.groupsReviewed)")
                statRow(label: L10n.photosToDelete, value: "\(deletionCount)")
                statRow(label: L10n.photosToKeep, value: "\(stats.photosToKeep)")
            }
            .padding()
            .background(QColors.surfaceSubtle)
            .clipShape(RoundedRectangle(cornerRadius: QRadius.md))

            Text(L10n.deletedPhotosNote)
                .font(QTypography.caption)
                .foregroundStyle(QColors.textTertiary)

            Button {
                performDeletion()
            } label: {
                Label(L10n.deleteNPhotos(deletionCount), systemImage: QIcons.delete)
            }
            .buttonStyle(.qDestructive)

            Button(L10n.cancel) {
                onFinished()
            }
            .buttonStyle(.qGhost)
        }
        .padding()
    }

    private var deletingView: some View {
        VStack(spacing: QSpacing.md) {
            ProgressView()
            Text(L10n.deletingPhotos)
                .foregroundStyle(QColors.textTertiary)
        }
    }

    private func allReviewedView(stats: ReviewStats) -> some View {
        VStack(spacing: QSpacing.lg) {
            QStatusIcon(QIcons.successFill, size: QSize.iconXLarge, color: QColors.success)

            Text(L10n.allDone)
                .font(QTypography.titleMedium)

            VStack(spacing: QSpacing.xs) {
                statRow(label: L10n.groupsReviewed, value: "\(stats.groupsReviewed)")
                statRow(label: L10n.photosCleaned, value: "\(stats.photosToDelete)")
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

    private func performDeletion() {
        guard let deps = dependencies,
              case .confirming(let ids, _) = reviewState.status else { return }
        reviewState.status = .deleting
        Task {
            do {
                try await deps.photoLibrary.deleteAssets(ids)
                let uuids = ids.map { deterministicUUID(from: $0) }
                try await deps.vectorStore.delete(ids: uuids)
                let stats = ReviewStats(
                    groupsReviewed: reviewState.keepSelections.count,
                    photosToDelete: ids.count,
                    photosToKeep: reviewState.keepSelections.count
                )
                reviewState.reduce(.didFinishDeletion(stats: stats))
            } catch let error as AppError {
                reviewState.reduce(.didFail(error))
            } catch {
                reviewState.reduce(.didFail(.unknown(error.localizedDescription)))
            }
        }
    }
}
