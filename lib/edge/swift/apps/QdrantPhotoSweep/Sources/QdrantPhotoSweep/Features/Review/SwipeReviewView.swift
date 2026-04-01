import SwiftUI

struct SwipeReviewView: View {
    @Environment(\.dependencies) private var dependencies
    @State private var state = ReviewState()

    let groups: [DuplicateGroup]
    let onFinished: () -> Void

    var body: some View {
        VStack {
            switch state.status {
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
        .navigationTitle("Review Duplicates")
        .task {
            state.reduce(.didLoadGroups(groups))
        }
    }

    private var emptyView: some View {
        VStack(spacing: QSpacing.md) {
            QStatusIcon(QIcons.sparkles, size: QSize.iconLarge, color: QColors.success)
            Text("No Duplicates Found")
                .font(QTypography.titleMedium)
            Text("Your photo library looks clean!")
                .foregroundStyle(QColors.textTertiary)

            Button("Done") {
                onFinished()
            }
            .buttonStyle(.qPrimary)
        }
    }

    private func reviewingView(index: Int, total: Int) -> some View {
        VStack(spacing: QSpacing.md) {
            HStack {
                Text("Group \(index + 1) of \(total)")
                    .font(QTypography.bodyLarge)
                Spacer()
                Button("Skip") {
                    withAnimation {
                        state.reduce(.didSkipGroup)
                    }
                }
                .buttonStyle(.qGhost)
            }
            .padding(.horizontal)

            ProgressView(value: Double(index), total: Double(total))
                .tint(QColors.primary)
                .padding(.horizontal)

            cardStack

            Text("Tap a photo to keep it, others will be marked for deletion")
                .font(QTypography.caption)
                .foregroundStyle(QColors.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
    }

    @ViewBuilder
    private var cardStack: some View {
        if let group = state.currentGroup {
            GroupComparisonView(
                group: group,
                selectedKeepId: state.keepSelections[group.id],
                onSelectKeep: { photo in
                    withAnimation(QAnimation.springDefault) {
                        state.reduce(.didSelectKeep(photo))
                    }
                }
            )
        }
    }

    private func confirmingView(deletionCount: Int, stats: ReviewStats) -> some View {
        VStack(spacing: QSpacing.lg) {
            QStatusIcon(QIcons.trashCircle, size: QSize.iconLarge, color: QColors.warning)

            Text("Ready to Clean Up")
                .font(QTypography.titleMedium)

            VStack(spacing: QSpacing.xs) {
                statRow(label: "Groups reviewed", value: "\(stats.groupsReviewed)")
                statRow(label: "Photos to delete", value: "\(deletionCount)")
                statRow(label: "Photos to keep", value: "\(stats.photosToKeep)")
            }
            .padding()
            .background(QColors.surfaceSubtle)
            .clipShape(RoundedRectangle(cornerRadius: QRadius.md))

            Text("Deleted photos will be moved to Recently Deleted")
                .font(QTypography.caption)
                .foregroundStyle(QColors.textTertiary)

            Button {
                performDeletion()
            } label: {
                Label("Delete \(deletionCount) Photos", systemImage: QIcons.delete)
            }
            .buttonStyle(.qDestructive)

            Button("Cancel") {
                onFinished()
            }
            .buttonStyle(.qGhost)
        }
        .padding()
    }

    private var deletingView: some View {
        VStack(spacing: QSpacing.md) {
            ProgressView()
            Text("Deleting photos...")
                .foregroundStyle(QColors.textTertiary)
        }
    }

    private func allReviewedView(stats: ReviewStats) -> some View {
        VStack(spacing: QSpacing.lg) {
            QStatusIcon(QIcons.successFill, size: QSize.iconXLarge, color: QColors.success)

            Text("All Done!")
                .font(QTypography.titleMedium)

            VStack(spacing: QSpacing.xs) {
                statRow(label: "Groups reviewed", value: "\(stats.groupsReviewed)")
                statRow(label: "Photos cleaned", value: "\(stats.photosToDelete)")
            }
            .padding()
            .background(QColors.surfaceSubtle)
            .clipShape(RoundedRectangle(cornerRadius: QRadius.md))

            Button("Finish") {
                onFinished()
            }
            .buttonStyle(.qPrimary)
        }
        .padding()
    }

    private func failedView(error: AppError) -> some View {
        VStack(spacing: QSpacing.md) {
            QStatusIcon(QIcons.warningFill, size: QSize.iconLarge, color: QColors.error)
            Text("Error")
                .font(QTypography.titleMedium)
            Text(error.localizedDescription)
                .font(QTypography.bodyMedium)
                .foregroundStyle(QColors.textTertiary)
                .multilineTextAlignment(.center)

            Button("Done") {
                onFinished()
            }
            .buttonStyle(.qPrimary)
        }
        .padding()
    }

    private func statRow(label: String, value: String) -> some View {
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
              case .confirming(let ids, _) = state.status else { return }
        state.status = .deleting
        Task {
            do {
                try await deps.photoLibrary.deleteAssets(ids)
                let uuids = ids.map { deterministicUUID(from: $0) }
                try await deps.vectorStore.delete(ids: uuids)
                let stats = ReviewStats(
                    groupsReviewed: state.keepSelections.count,
                    photosToDelete: ids.count,
                    photosToKeep: state.keepSelections.count
                )
                state.reduce(.didFinishDeletion(stats: stats))
            } catch let error as AppError {
                state.reduce(.didFail(error))
            } catch {
                state.reduce(.didFail(.unknown(error.localizedDescription)))
            }
        }
    }
}
