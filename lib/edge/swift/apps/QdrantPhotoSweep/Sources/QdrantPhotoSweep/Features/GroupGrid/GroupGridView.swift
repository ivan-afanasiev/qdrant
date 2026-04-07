import SwiftUI
import Photos

struct InlineGroupGridView: View {
    var state: GroupGridState
    let useCases: GroupGridFeature.UseCases?
    let reviewUseCases: ReviewFeature.UseCases?
    let onGroupReviewed: (UUID) -> Void

    private let columns = [
        GridItem(.flexible(), spacing: QSpacing.xs),
        GridItem(.flexible(), spacing: QSpacing.xs)
    ]

    var body: some View {
        gridRoot
            .navigationDestination(for: GroupSummary.self) { summary in
                groupDestination(for: summary.id)
            }
            .task {
                if state.status == .idle {
                    loadFirstPage()
                }
            }
    }

    // MARK: - Grid Root

    @ViewBuilder
    private var gridRoot: some View {
        switch state.status {
        case .idle, .loading where state.groups.isEmpty:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .loaded, .loading:
            gridContent

        case .failed(let error):
            VStack(spacing: QSpacing.md) {
                QStatusIcon(QIcons.warningFill, size: QSize.iconLarge, color: QColors.error)
                Text(error.localizedDescription)
                    .font(QTypography.bodyMedium)
                    .foregroundStyle(QColors.textTertiary)
                    .multilineTextAlignment(.center)

                Button(L10n.retry) { loadFirstPage() }
                    .buttonStyle(.qPrimary)
            }
            .padding()
        }
    }

    private var gridContent: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: QSpacing.xs) {
                ForEach(state.groups) { summary in
                    NavigationLink(value: summary) {
                        GroupGridCell(summary: summary)
                    }
                    .buttonStyle(.plain)
                    .onAppear {
                        if summary.id == state.groups.last?.id, state.hasMore {
                            loadNextPage()
                        }
                    }
                }
            }
            .padding(.horizontal, QSpacing.xs)
            .padding(.top, QSpacing.xs)

            if state.status == .loading {
                ProgressView()
                    .padding()
            }
        }
    }

    // MARK: - Navigation Destination

    @ViewBuilder
    private func groupDestination(for groupId: UUID) -> some View {
        if let useCases, let reviewUseCases {
            GroupDetailLoader(
                groupId: groupId,
                useCases: useCases,
                reviewUseCases: reviewUseCases,
                onGroupReviewed: onGroupReviewed
            )
        }
    }

    // MARK: - Actions

    private func loadFirstPage() {
        guard let useCases else { return }
        state.reduce(.didStartLoading)
        Task {
            do {
                let output = try await useCases.loadPage.execute(
                    GroupsPageInput(offset: 0, limit: GroupGridFeature.pageSize)
                )
                state.reduce(.didLoadPage(output, isFirstPage: true))
            } catch {
                state.reduce(.didFail(error as? AppError ?? .unknown(error.localizedDescription)))
            }
        }
    }

    private func loadNextPage() {
        guard let useCases, state.status != .loading else { return }
        state.reduce(.didStartLoading)
        Task {
            do {
                let output = try await useCases.loadPage.execute(
                    GroupsPageInput(offset: state.currentOffset, limit: GroupGridFeature.pageSize)
                )
                state.reduce(.didLoadPage(output, isFirstPage: false))
            } catch {
                state.reduce(.didFail(error as? AppError ?? .unknown(error.localizedDescription)))
            }
        }
    }
}

// MARK: - Group Detail Loader

private struct GroupDetailLoader: View {
    let groupId: UUID
    let useCases: GroupGridFeature.UseCases
    let reviewUseCases: ReviewFeature.UseCases
    let onGroupReviewed: (UUID) -> Void

    @State private var group: DuplicateGroup?
    @State private var isLoading = true
    @State private var loadError: AppError?

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let group {
                SingleGroupReviewView(
                    group: group,
                    reviewUseCases: reviewUseCases,
                    onGroupReviewed: onGroupReviewed
                )
            } else if let loadError {
                VStack(spacing: QSpacing.md) {
                    QStatusIcon(QIcons.warningFill, size: QSize.iconLarge, color: QColors.error)
                    Text(loadError.localizedDescription)
                        .font(QTypography.bodyMedium)
                        .foregroundStyle(QColors.textTertiary)
                }
            }
        }
        .task { await loadGroup() }
    }

    private func loadGroup() async {
        do {
            group = try await useCases.loadGroup.execute(groupId)
            isLoading = false
        } catch {
            loadError = error as? AppError ?? .unknown(error.localizedDescription)
            isLoading = false
        }
    }
}

// MARK: - Grid Cell

struct GroupGridCell: View {
    let summary: GroupSummary

    @State private var thumbnail: CGImage?
    @State private var fullImage: CGImage?
    @State private var isLoadingFull = false
    @State private var aspectRatio: CGFloat?

    private var computedAspectRatio: CGFloat {
        guard summary.representativePixelWidth > 0, summary.representativePixelHeight > 0 else { return 1 }
        return CGFloat(summary.representativePixelWidth) / CGFloat(summary.representativePixelHeight)
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            imageContent

            loadingIndicator

            HStack(spacing: QSpacing.xxs) {
                Image(systemName: QIcons.photoStackFill)
                    .font(QTypography.captionSmall)
                Text("\(summary.photoCount)")
                    .font(QTypography.numericSmall)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, QSpacing.xs)
            .padding(.vertical, QSpacing.xxs)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: QRadius.xs))
            .padding(QSpacing.xs)
        }
        .clipShape(RoundedRectangle(cornerRadius: QRadius.md))
        .qShadow(QShadow.sm)
        .task { await loadImages() }
    }

    @ViewBuilder
    private var imageContent: some View {
        let displayImage = fullImage ?? thumbnail
        if let image = displayImage {
            let ratio = aspectRatio ?? computedAspectRatio
            Image(decorative: image, scale: 1)
                .resizable()
                .aspectRatio(ratio, contentMode: .fit)
        } else {
            Rectangle()
                .fill(QColors.surfaceSubtle)
                .aspectRatio(computedAspectRatio, contentMode: .fit)
                .overlay { ProgressView() }
        }
    }

    @ViewBuilder
    private var loadingIndicator: some View {
        if isLoadingFull, thumbnail != nil {
            VStack {
                HStack {
                    ProgressView()
                        .tint(.white)
                        .padding(QSpacing.xxs)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                        .padding(QSpacing.xxs)
                    Spacer()
                }
                Spacer()
            }
        }
    }

    private func loadImages() async {
        let fetchResult = PHAsset.fetchAssets(
            withLocalIdentifiers: [summary.representativeAssetId],
            options: nil
        )
        guard let phAsset = fetchResult.firstObject else { return }
        let ratio = CGFloat(phAsset.pixelWidth) / max(CGFloat(phAsset.pixelHeight), 1)
        self.aspectRatio = ratio

        if let fast = try? await loadCGImage(for: phAsset, targetSize: QSize.thumbnailRequest) {
            self.thumbnail = fast
        }

        isLoadingFull = true
        let targetSize = CGSize(
            width: Swift.min(CGFloat(phAsset.pixelWidth), 600),
            height: Swift.min(CGFloat(phAsset.pixelHeight), 600)
        )
        if let hq = try? await loadHighQualityCGImage(for: phAsset, targetSize: targetSize) {
            self.fullImage = hq
        }
        isLoadingFull = false
    }
}
