import SwiftUI

struct SwipeReviewView: View {
    @Environment(\.dependencies) private var dependencies
    @State private var reviewState = ReviewState()
    @State private var fullscreenPhoto: PhotoReference?
    @State private var dragOffset: CGFloat = 0
    @State private var showGroupGrid = false

    let onFinished: () -> Void

    private var useCases: ReviewFeature.UseCases? {
        dependencies?.reviewUseCases
    }

    private var groupGridUseCases: GroupGridFeature.UseCases? {
        dependencies?.groupGridUseCases
    }

    var body: some View {
        Group {
            switch reviewState.status {
            case .idle, .loading:
                ProgressView()

            case .noMoreGroups:
                emptyView

            case .reviewing:
                reviewingView

            case .deletingGroup:
                ReviewDeletingView()

            case .allReviewed:
                ReviewAllDoneView(stats: reviewState.stats, onFinished: onFinished)

            case .failed(let error):
                ReviewFailedView(error: error, onDismiss: onFinished)
            }
        }
        .navigationTitle(L10n.reviewDuplicates)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showGroupGrid = true
                } label: {
                    Image(systemName: QIcons.squareGrid)
                }
            }
        }
        .sheet(isPresented: $showGroupGrid) {
            if let groupGridUseCases, let useCases {
                GroupGridView(
                    useCases: groupGridUseCases,
                    reviewUseCases: useCases
                )
            }
        }
        .task { await loadNextGroup() }
        .onChange(of: reviewState.status) { _, newStatus in
            if newStatus == .loading {
                Task { await loadNextGroup() }
            }
        }
        .fullScreenCover(item: $fullscreenPhoto) { photo in
            FullscreenPhotoView(photo: photo) {
                fullscreenPhoto = nil
            }
        }
    }

    // MARK: - Empty

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

    // MARK: - Reviewing

    private var reviewingView: some View {
        VStack(spacing: QSpacing.md) {
            headerBar

            if reviewState.totalGroups > 0 {
                ProgressView(value: Double(reviewState.reviewedInSession), total: Double(reviewState.totalGroups))
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
        }
    }

    private var headerBar: some View {
        HStack {
            Text(L10n.groupNofTotal(reviewState.reviewedInSession + 1, reviewState.totalGroups))
                .font(QTypography.bodyLarge)
                .contentTransition(.numericText())
                .animation(.default, value: reviewState.reviewedInSession)
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

    // MARK: - Actions (use case delegation)

    private func loadNextGroup() async {
        guard let useCases else { return }
        reviewState.reduce(.didStartLoading)
        do {
            let output = try await useCases.loadNextGroup.execute(())
            guard let group = output.group else {
                reviewState.reduce(.didLoadEmpty)
                return
            }
            reviewState.reduce(.didLoadGroup(group, pendingCount: output.pendingCount))
        } catch {
            reviewState.reduce(.didFail(error as? AppError ?? .unknown(error.localizedDescription)))
        }
    }

    private func deleteCurrentGroup() {
        guard let useCases, let group = reviewState.currentGroup else { return }
        let keptIds = reviewState.keptIds(for: group)
        reviewState.reduce(.didConfirmGroup)

        Task {
            do {
                let result = try await useCases.deleteGroup.execute(
                    DeleteGroupInput(group: group, keptIds: keptIds)
                )
                reviewState.reduce(.didFinishGroupDeletion(deleted: result.deleted, kept: result.kept))
            } catch {
                reviewState.reduce(.didFail(error as? AppError ?? .unknown(error.localizedDescription)))
            }
        }
    }

    private func skipCurrentGroup() {
        guard let useCases, let group = reviewState.currentGroup else { return }
        reviewState.reduce(.didSkipGroup)
        Task {
            try? await useCases.skipGroup.execute(SkipGroupInput(group: group))
        }
    }
}
