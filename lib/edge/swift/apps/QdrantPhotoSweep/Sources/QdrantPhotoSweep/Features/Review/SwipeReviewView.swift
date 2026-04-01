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

            case .complete:
                reviewContent

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
        guard detectionState.status == .idle else { return }
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
            HStack {
                Text(L10n.groupNofTotal(reviewState.currentIndex + 1, reviewState.totalGroups))
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

            ProgressView(value: Double(reviewState.currentIndex), total: Double(reviewState.totalGroups))
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
                    deleteCurrentGroup()
                } label: {
                    Label(L10n.deleteNPhotos(deleteCount), systemImage: QIcons.delete)
                }
                .buttonStyle(.qDestructive)
                .padding(.horizontal)

            case false:
                Button {
                    withAnimation {
                        reviewState.reduce(.didSkipGroup)
                    }
                } label: {
                    Text(L10n.skip)
                }
                .buttonStyle(.qGhost)
                .padding(.horizontal)
            }
        }
    }

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
        let keptCount = reviewState.keptIds(for: group).count

        reviewState.reduce(.didConfirmGroup)

        guard !idsToDelete.isEmpty else {
            reviewState.reduce(.didFinishGroupDeletion(deleted: 0, kept: keptCount))
            return
        }

        Task {
            do {
                try await deps.photoLibrary.deleteAssets(idsToDelete)
                let uuids = idsToDelete.map { deterministicUUID(from: $0) }
                try await deps.vectorStore.delete(ids: uuids)
                reviewState.reduce(.didFinishGroupDeletion(deleted: idsToDelete.count, kept: keptCount))
            } catch let error as AppError {
                reviewState.reduce(.didFail(error))
            } catch {
                reviewState.reduce(.didFail(.unknown(error.localizedDescription)))
            }
        }
    }
}
