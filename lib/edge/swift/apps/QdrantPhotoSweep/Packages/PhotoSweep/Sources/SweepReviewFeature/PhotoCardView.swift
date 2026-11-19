import SwiftUI
import SweepDesignSystem
import SweepDomain

/// One photo card. Shows a thumbnail first, then replaces it with a high-quality image sized
/// to the card once it is on screen; a spinner in the top-left corner shows it is loading.
/// The full original is decoded only by the full-screen preview, which keeps memory bounded
/// for large groups.
struct PhotoCardView: View {
    static let thumbnailPixels = 800

    let asset: AssetID
    let photo: PhotoAsset?
    let isKept: Bool
    let images: ReviewImages
    let onTap: () -> Void
    let onPreview: () -> Void
    @State private var thumbnail: CGImage?
    @State private var original: CGImage?
    @State private var isLoadingOriginal = false
    @State private var cardWidth: CGFloat = 0
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .bottomLeading) {
                image
                dateLabel
                    .padding(QSpacing.xs)
            }
            .overlay(alignment: .topLeading) {
                if isLoadingOriginal, thumbnail != nil {
                    ProgressView()
                        .controlSize(.small)
                        .padding(QSpacing.xs)
                        .glassEffect(.regular, in: .circle)
                        .padding(QSpacing.xs)
                        .accessibilityHidden(true)
                }
            }
            .overlay(alignment: .topTrailing) {
                if isKept {
                    Image(systemName: QIcons.successFill)
                        .font(QTypography.titleMedium)
                        .foregroundStyle(QColors.success)
                        .padding(QSpacing.xs)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                Button(action: onPreview) {
                    Image(systemName: QIcons.fullscreen)
                        .font(QTypography.iconButton)
                        .padding(QSpacing.xs)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .padding(QSpacing.xs)
                .accessibilityLabel(Text(L10n.preview))
            }
            .clipShape(RoundedRectangle(cornerRadius: QRadius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: QRadius.lg)
                    .stroke(isKept ? QColors.success : Color.clear, lineWidth: 3)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isKept ? .isSelected : [])
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { cardWidth = $0 }
        .task(id: DisplayRequest(asset: asset, maxPixels: displayPixels)) {
            if thumbnail == nil {
                thumbnail = await images.thumbnail(asset, Self.thumbnailPixels)
            }
            // Always replace the placeholder: the 800 px thumbnail is Photos' fast, low-quality
            // image, so even a smaller high-quality image (half-width grid cards) is sharper.
            guard !Task.isCancelled, displayPixels > 0 else { return }
            isLoadingOriginal = true
            let loaded = await images.display(asset, displayPixels)
            isLoadingOriginal = false
            // Cancelled when the card leaves the screen; keep the thumbnail in that case.
            guard !Task.isCancelled, let loaded else { return }
            original = loaded
        }
    }

    private struct DisplayRequest: Equatable {
        let asset: AssetID
        let maxPixels: Int
    }

    /// Longest side in pixels at the card's displayed size, rounded up to a 256 px step so
    /// small layout changes do not reload, and capped at 4096.
    private var displayPixels: Int {
        guard cardWidth > 0 else { return 0 }
        let longest = cardWidth * displayScale / min(aspectRatio, 1)
        let rounded = Int((longest / 256).rounded(.up)) * 256
        return min(rounded, 4096)
    }

    @ViewBuilder
    private var image: some View {
        if let shown = original ?? thumbnail {
            Image(decorative: shown, scale: 1)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Rectangle()
                .fill(QColors.surfaceSubtle)
                .aspectRatio(aspectRatio, contentMode: .fit)
                .overlay { ProgressView() }
        }
    }

    private var aspectRatio: CGFloat {
        guard let photo, photo.pixelWidth > 0, photo.pixelHeight > 0 else { return 1 }
        return CGFloat(photo.pixelWidth) / CGFloat(photo.pixelHeight)
    }

    @ViewBuilder
    private var dateLabel: some View {
        Group {
            if let date = photo?.creationDate {
                Text(date, style: .date)
            } else {
                Text(L10n.unknownDate)
            }
        }
        .font(QTypography.captionSmall)
        .padding(.horizontal, QSpacing.xs)
        .padding(.vertical, QSpacing.xxs)
        .glassEffect(.regular, in: .rect(cornerRadius: QRadius.sm))
    }
}
