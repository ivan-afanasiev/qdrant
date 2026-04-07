import SwiftUI

struct SingleGroupReviewView: View {
    @Environment(\.dismiss) private var dismiss
    let group: DuplicateGroup
    let reviewUseCases: ReviewFeature.UseCases
    let onGroupReviewed: (UUID) -> Void

    @State private var keptIds: Set<String>
    @State private var dragOffset: CGFloat = 0
    @State private var fullscreenPhoto: PhotoReference?
    @State private var isDeleting = false

    init(
        group: DuplicateGroup,
        reviewUseCases: ReviewFeature.UseCases,
        onGroupReviewed: @escaping (UUID) -> Void
    ) {
        self.group = group
        self.reviewUseCases = reviewUseCases
        self.onGroupReviewed = onGroupReviewed
        self._keptIds = State(initialValue: [group.bestCandidate.id])
    }

    var body: some View {
        VStack(spacing: QSpacing.md) {
            if isDeleting {
                Spacer()
                ReviewDeletingView()
                Spacer()
            } else {
                Text(L10n.similarPhotos(group.count))
                    .font(QTypography.bodyLarge)
                    .padding(.top, QSpacing.sm)

                ReviewCardStack(
                    group: group,
                    keptIds: keptIds,
                    dragOffset: $dragOffset,
                    fullscreenPhoto: $fullscreenPhoto,
                    onToggleKeep: { photo in
                        withAnimation(QAnimation.springDefault) {
                            toggleKeep(photo)
                        }
                    },
                    onSwipedOut: { skipGroup() }
                )

                ReviewConfirmButton(
                    group: group,
                    keptIds: keptIds,
                    onDelete: { deleteGroup() },
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
        .navigationTitle(L10n.reviewDuplicates)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $fullscreenPhoto) { photo in
            FullscreenPhotoView(photo: photo) {
                fullscreenPhoto = nil
            }
        }
    }

    // MARK: - Actions

    private func toggleKeep(_ photo: PhotoReference) {
        if keptIds.contains(photo.id) {
            keptIds.remove(photo.id)
        } else {
            keptIds.insert(photo.id)
        }
    }

    private func deleteGroup() {
        isDeleting = true
        Task {
            do {
                _ = try await reviewUseCases.deleteGroup.execute(
                    DeleteGroupInput(group: group, keptIds: keptIds)
                )
                notifyAndPop()
            } catch {
                isDeleting = false
            }
        }
    }

    private func skipGroup() {
        Task {
            try? await reviewUseCases.skipGroup.execute(SkipGroupInput(group: group))
            notifyAndPop()
        }
    }

    private func animateSkip() {
        let screenWidth = UIScreen.main.bounds.width
        withAnimation(.easeIn(duration: 0.25)) {
            dragOffset = -screenWidth * 1.5
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            dragOffset = 0
            skipGroup()
        }
    }

    private func notifyAndPop() {
        guard let groupUUID = UUID(uuidString: group.id) else { return }
        onGroupReviewed(groupUUID)
        dismiss()
    }
}
