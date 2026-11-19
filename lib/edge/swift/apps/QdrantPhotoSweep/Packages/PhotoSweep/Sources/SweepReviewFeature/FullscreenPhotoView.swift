import SwiftUI
import SweepDesignSystem
import SweepDomain

/// Full-resolution preview with zoom.
struct FullscreenPhotoView: View {
    let assets: [AssetID]
    @State private var asset: AssetID
    @State private var pagingOffset: CGFloat = 0
    @State private var isPaging: Bool = false
    @State private var dragAxis: DragAxis?

    private enum DragAxis { case horizontal, vertical, pan }
    let images: ReviewImages
    let onDismiss: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dismissalOffset: CGSize = .zero
    @State private var isDismissing: Bool = false
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    init(assets: [AssetID], selected: AssetID, images: ReviewImages, onDismiss: @escaping () -> Void) {
        self.assets = assets
        self.images = images
        self.onDismiss = onDismiss
        _asset = State(initialValue: selected)
    }

    private var selectedIndex: Int { assets.firstIndex(of: asset) ?? 0 }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topTrailing) {
                Color.black.opacity(backdropOpacity).ignoresSafeArea()
                ZStack {
                    ForEach(visibleAssets, id: \.self) { pageAsset in
                        FullscreenImagePage(asset: pageAsset, isSelected: pageAsset == asset, images: images)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .offset(x: CGFloat((assets.firstIndex(of: pageAsset) ?? 0) - selectedIndex) * geometry.size.width)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .scaleEffect(scale)
                .scaleEffect(reduceMotion ? 1 : 1 - dismissalProgress * 0.12)
                .offset(x: pagingOffset)
                .offset(offset)
                .offset(dismissalOffset)
                .opacity(isDismissing ? 0 : 1)
                .gesture(magnification)
                .simultaneousGesture(pan(in: geometry.size))
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
                .opacity(1 - dismissalProgress)
            }
            .allowsHitTesting(!isDismissing && !isPaging)
        }
        .presentationBackground(.clear)
        .statusBarHidden()

    }

    private var visibleAssets: [AssetID] {
        Array(assets[max(0, selectedIndex - 1)..<min(assets.count, selectedIndex + 2)])
    }

    private func finishPaging(_ value: DragGesture.Value, width: CGFloat) {
        let travel = value.predictedEndTranslation.width
        let step = travel < 0 ? 1 : -1
        let next = selectedIndex + step
        guard abs(travel) > width * 0.25, assets.indices.contains(next) else {
            withAnimation(QAnimation.springDefault) { pagingOffset = 0 }
            return
        }
        isPaging = true
        withAnimation(reduceMotion ? .linear(duration: 0.1) : .easeOut(duration: 0.22)) {
            pagingOffset = step > 0 ? -width : width
        } completion: {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                asset = assets[next]
                pagingOffset = 0
                scale = 1
                lastScale = 1
                offset = .zero
                lastOffset = .zero
                isPaging = false
            }
        }
    }

    private var magnification: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                dismissalOffset = .zero
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

    private var dismissalProgress: CGFloat {
        min(abs(dismissalOffset.height) / 300, 1)
    }

    private var backdropOpacity: Double {
        isDismissing ? 0 : Double(1 - dismissalProgress * 0.8)
    }

    private func finishDismissal(in size: CGSize) {
        withAnimation(.easeOut(duration: reduceMotion ? 0.15 : 0.22)) {
            isDismissing = true
            if !reduceMotion {
                dismissalOffset.height = dismissalOffset.height < 0 ? -size.height : size.height
            }
        } completion: {
            // The interactive transition already finished; avoid a second modal slide.
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { onDismiss() }
        }
    }

    private func pan(in size: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                guard !isDismissing else { return }
                if dragAxis == nil {
                    dragAxis = scale > 1 ? .pan : (abs(value.translation.width) > abs(value.translation.height) ? .horizontal : .vertical)
                }
                if dragAxis == .horizontal {
                    let translation = value.translation.width
                    let atEdge = (selectedIndex == 0 && translation > 0) || (selectedIndex == assets.count - 1 && translation < 0)
                    pagingOffset = atEdge ? translation * 0.25 : translation
                    return
                }
                if dragAxis == .vertical {
                    dismissalOffset = value.translation
                    return
                }
                offset = CGSize(width: lastOffset.width + value.translation.width, height: lastOffset.height + value.translation.height)
            }
            .onEnded { value in
                defer { dragAxis = nil }
                if dragAxis == .horizontal {
                    finishPaging(value, width: size.width)
                    return
                }
                if dragAxis == .vertical {
                    let distance: CGFloat = abs(dismissalOffset.height)
                    let projectedDistance: CGFloat = abs(value.predictedEndTranslation.height)
                    let threshold: CGFloat = max(100, size.height * 0.18)
                    if distance > threshold || (distance > 40 && projectedDistance > size.height * 0.4) {
                        finishDismissal(in: size)
                    } else {
                        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : QAnimation.springDefault) {
                            dismissalOffset = .zero
                        }
                    }
                } else {
                    lastOffset = offset
                }
            }
    }
}

/// Only the current page requests an original; neighbors retain lightweight previews.
private struct FullscreenImagePage: View {
    let asset: AssetID
    let isSelected: Bool
    let images: ReviewImages
    @State private var image: CGImage?

    var body: some View {
        ZStack {
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                ProgressView().tint(.white)
            }
        }
        .task(id: isSelected) {
            image = nil
            let preview = await images.thumbnail(asset, 512)
            guard !Task.isCancelled else { return }
            image = preview
            if isSelected {
                let original = await images.original(asset)
                guard !Task.isCancelled else { return }
                if let original { image = original }
            }
        }
    }
}
