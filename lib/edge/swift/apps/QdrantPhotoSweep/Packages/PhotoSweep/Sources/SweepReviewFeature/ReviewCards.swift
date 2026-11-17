#if os(iOS)
import SwiftUI
import SweepDesignSystem
import SweepDomain

/// Swipeable card container ported from the legacy app. Swiping either way skips the group.
struct ReviewCardStack<Content: View>: View {
    let snapshot: ReviewGroupSnapshot
    @Binding var dragOffset: CGFloat
    let onSwipedOut: () -> Void
    @ViewBuilder let content: () -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isDragging: Bool { dragOffset != 0 }

    var body: some View {
        GeometryReader { geometry in
            content()
                .id(snapshot.id)
                .offset(x: dragOffset)
                .rotationEffect(.degrees(reduceMotion ? 0 : Double(dragOffset) / 30), anchor: .bottom)
                .opacity(1 - Double(abs(dragOffset) / 200) * 0.3)
                .allowsHitTesting(!isDragging)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
                .simultaneousGesture(swipeGesture(width: geometry.size.width))
                .animation(QAnimation.springDefault, value: snapshot.id)
        }
    }

    private func swipeGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                dragOffset = value.translation.width
            }
            .onEnded { value in
                guard dragOffset != 0 else { return }
                let threshold = width * 0.3
                let velocity = value.predictedEndTranslation.width
                if abs(value.translation.width) > threshold || abs(velocity) > 500 {
                    let exit = (value.translation.width < 0 ? -1 : 1) * width * 1.5
                    withAnimation(.easeIn(duration: 0.25)) {
                        dragOffset = exit
                    } completion: {
                        dragOffset = 0
                        onSwipedOut()
                    }
                } else {
                    withAnimation(QAnimation.springDefault) {
                        dragOffset = 0
                    }
                }
            }
    }
}

/// All photos of one group; tap to keep, expand for preview.
struct GroupComparisonView: View {
    let snapshot: ReviewGroupSnapshot
    let keep: Set<AssetID>
    let details: [AssetID: PhotoAsset]
    let images: ReviewImages
    let onToggleKeep: (AssetID) -> Void
    let onPreview: (AssetID) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: QSpacing.sm) {
                Text(L10n.tapToKeepHint)
                    .font(QTypography.bodySmall)
                    .foregroundStyle(QColors.textSecondary)
                    .multilineTextAlignment(.center)
                Text(L10n.similarPhotos(snapshot.members.count))
                    .font(QTypography.bodyMedium)
                    .foregroundStyle(QColors.textTertiary)
                LazyVGrid(columns: columns, spacing: QSpacing.sm) {
                    ForEach(snapshot.members, id: \.self) { asset in
                        PhotoCardView(
                            asset: asset,
                            photo: details[asset],
                            isKept: keep.contains(asset),
                            images: images,
                            onTap: { onToggleKeep(asset) },
                            onPreview: { onPreview(asset) }
                        )
                    }
                }
            }
            .padding()
        }
    }

    private var columns: [GridItem] {
        snapshot.members.count <= 2
            ? [GridItem(.flexible())]
            : [GridItem(.flexible()), GridItem(.flexible())]
    }
}

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
            guard !Task.isCancelled, displayPixels > Self.thumbnailPixels else { return }
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

/// Full-resolution preview with zoom.
struct FullscreenPhotoView: View {
    let asset: AssetID
    let images: ReviewImages
    let onDismiss: () -> Void
    @State private var image: CGImage?
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            Group {
                if let image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    ProgressView().tint(.white)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .scaleEffect(scale)
            .offset(offset)
            .gesture(magnification)
            .simultaneousGesture(pan)
            .onTapGesture(count: 2) {
                withAnimation(QAnimation.springDefault) {
                    scale = scale > 1.5 ? 1 : 3
                    if scale == 1 { offset = .zero }
                    lastScale = scale
                    lastOffset = offset
                }
            }

            Button(action: onDismiss) {
                Image(systemName: QIcons.xmark)
                    .font(QTypography.dismissButton)
                    .padding(QSpacing.sm)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .padding(QSpacing.md)
            .accessibilityLabel(Text(L10n.close))
        }
        .statusBarHidden()
        .task {
            image = await images.original(asset)
        }
    }

    private var magnification: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                scale = min(max(lastScale * value.magnification, 0.5), 10)
            }
            .onEnded { _ in
                withAnimation(QAnimation.springDefault) {
                    scale = min(max(scale, 1), 6)
                    if scale <= 1 { offset = .zero }
                }
                lastScale = scale
                if scale <= 1 { lastOffset = .zero }
            }
    }

    private var pan: some Gesture {
        DragGesture()
            .onChanged { value in
                guard scale > 1 else { return }
                offset = CGSize(width: lastOffset.width + value.translation.width, height: lastOffset.height + value.translation.height)
            }
            .onEnded { _ in lastOffset = offset }
    }
}
#endif
