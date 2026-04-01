import SwiftUI
import Photos

struct PhotoCardView: View {
    let photo: PhotoReference
    let isSelected: Bool
    let onTap: () -> Void
    let onFullscreen: () -> Void

    @State private var thumbnail: CGImage?
    @State private var fullImage: CGImage?
    @State private var isLoadingFull = false
    @State private var aspectRatio: CGFloat?

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .bottomLeading) {
                imageContent
                dateOverlay
                selectionBadge
                fullscreenButton
                loadingIndicator
            }
            .clipShape(RoundedRectangle(cornerRadius: QRadius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: QRadius.lg)
                    .stroke(isSelected ? QColors.success : Color.clear, lineWidth: 3)
            )
            .qShadow(QShadow.md)
        }
        .buttonStyle(.plain)
        .task {
            await loadImages()
        }
    }

    @ViewBuilder
    private var imageContent: some View {
        let displayImage = fullImage ?? thumbnail
        switch displayImage {
        case .some(let image):
            let ratio = aspectRatio ?? 1
            Image(decorative: image, scale: 1)
                .resizable()
                .aspectRatio(ratio, contentMode: .fit)

        case .none:
            Rectangle()
                .fill(QColors.surfaceSubtle)
                .aspectRatio(computedAspectRatio, contentMode: .fit)
                .overlay { ProgressView() }
        }
    }

    private var computedAspectRatio: CGFloat {
        guard photo.pixelWidth > 0, photo.pixelHeight > 0 else { return 1 }
        return CGFloat(photo.pixelWidth) / CGFloat(photo.pixelHeight)
    }

    @ViewBuilder
    private var loadingIndicator: some View {
        if isLoadingFull, thumbnail != nil {
            VStack {
                HStack {
                    ProgressView()
                        .tint(.white)
                        .padding(QSpacing.xs)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                        .padding(QSpacing.xs)
                    Spacer()
                }
                Spacer()
            }
        }
    }

    private var dateOverlay: some View {
        Group {
            switch photo.creationDate {
            case .some(let date):
                Text(date, style: .date)
                    .font(QTypography.captionSmall)
            case .none:
                Text(L10n.unknownDate)
                    .font(QTypography.captionSmall)
                    .foregroundStyle(QColors.textTertiary)
            }
        }
        .padding(.horizontal, QSpacing.xs)
        .padding(.vertical, QSpacing.xxs)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: QRadius.sm))
        .padding(QSpacing.xs)
    }

    @ViewBuilder
    private var selectionBadge: some View {
        if isSelected {
            VStack {
                HStack {
                    Spacer()
                    Image(systemName: QIcons.successFill)
                        .font(QTypography.titleMedium)
                        .foregroundStyle(QColors.success)
                        .padding(QSpacing.xs)
                }
                Spacer()
            }
        }
    }

    private var fullscreenButton: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Button {
                    onFullscreen()
                } label: {
                    Image(systemName: QIcons.fullscreen)
                        .font(QTypography.iconButton)
                        .foregroundStyle(.white)
                        .padding(QSpacing.xs)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                }
                .padding(QSpacing.xs)
            }
        }
    }

    private func loadImages() async {
        let fetchResult = PHAsset.fetchAssets(
            withLocalIdentifiers: [photo.assetId],
            options: nil
        )
        guard let phAsset = fetchResult.firstObject else { return }
        let ratio = CGFloat(phAsset.pixelWidth) / max(CGFloat(phAsset.pixelHeight), 1)
        self.aspectRatio = ratio

        // Phase 1: fast thumbnail for immediate display
        if let fast = try? await loadCGImage(for: phAsset, targetSize: QSize.thumbnailRequest) {
            self.thumbnail = fast
        }

        // Phase 2: high-quality image at screen-appropriate size
        isLoadingFull = true
        let targetSize = CGSize(
            width: Swift.min(CGFloat(phAsset.pixelWidth), 1200),
            height: Swift.min(CGFloat(phAsset.pixelHeight), 1200)
        )
        if let hq = try? await loadHighQualityCGImage(for: phAsset, targetSize: targetSize) {
            self.fullImage = hq
        }
        isLoadingFull = false
    }
}
 
