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
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 48))
                .foregroundStyle(.green)
            Text("No Duplicates Found")
                .font(.title2.bold())
            Text("Your photo library looks clean!")
                .foregroundStyle(.secondary)

            Button("Done") {
                onFinished()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func reviewingView(index: Int, total: Int) -> some View {
        VStack(spacing: 16) {
            HStack {
                Text("Group \(index + 1) of \(total)")
                    .font(.headline)
                Spacer()
                Button("Skip") {
                    withAnimation {
                        state.reduce(.didSkipGroup)
                    }
                }
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal)

            ProgressView(value: Double(index), total: Double(total))
                .padding(.horizontal)

            cardStack

            Text("Tap a photo to keep it, others will be marked for deletion")
                .font(.caption)
                .foregroundStyle(.secondary)
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
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        state.reduce(.didSelectKeep(photo))
                    }
                }
            )
        }
    }

    private func confirmingView(deletionCount: Int, stats: ReviewStats) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "trash.circle")
                .font(.system(size: 48))
                .foregroundStyle(.orange)

            Text("Ready to Clean Up")
                .font(.title2.bold())

            VStack(spacing: 8) {
                statRow(label: "Groups reviewed", value: "\(stats.groupsReviewed)")
                statRow(label: "Photos to delete", value: "\(deletionCount)")
                statRow(label: "Photos to keep", value: "\(stats.photosToKeep)")
            }
            .padding()
            .background(.fill.quaternary)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Text("Deleted photos will be moved to Recently Deleted")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button(role: .destructive) {
                performDeletion()
            } label: {
                Label("Delete \(deletionCount) Photos", systemImage: "trash")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)

            Button("Cancel") {
                onFinished()
            }
            .foregroundStyle(.secondary)
        }
        .padding()
    }

    private var deletingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Deleting photos...")
                .foregroundStyle(.secondary)
        }
    }

    private func allReviewedView(stats: ReviewStats) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)

            Text("All Done!")
                .font(.title2.bold())

            VStack(spacing: 8) {
                statRow(label: "Groups reviewed", value: "\(stats.groupsReviewed)")
                statRow(label: "Photos cleaned", value: "\(stats.photosToDelete)")
            }
            .padding()
            .background(.fill.quaternary)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Button("Finish") {
                onFinished()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    private func failedView(error: AppError) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.red)
            Text("Error")
                .font(.title2.bold())
            Text(error.localizedDescription)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Done") {
                onFinished()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    private func statRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.headline.monospacedDigit())
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
