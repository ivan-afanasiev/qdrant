import SwiftUI
import Photos

struct FullscreenPhotoView: View {
    let photo: PhotoReference
    let onDismiss: () -> Void

    @State private var image: CGImage?
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()

                imageLayer(in: geo.size)
                    .scaleEffect(scale)
                    .offset(offset)
                    .gesture(dragGesture)
                    .gesture(magnificationGesture)
                    .onTapGesture(count: 2) {
                        withAnimation(QAnimation.springDefault) {
                            switch scale > 1.5 {
                            case true:
                                scale = 1
                                offset = .zero
                            case false:
                                scale = 3
                            }
                            lastScale = scale
                            lastOffset = offset
                        }
                    }

                dismissButton
            }
        }
        .statusBar(hidden: true)
        .task {
            await loadFullResolution()
        }
    }

    @ViewBuilder
    private func imageLayer(in containerSize: CGSize) -> some View {
        switch image {
        case .some(let cgImage):
            Image(decorative: cgImage, scale: 1)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: containerSize.width, maxHeight: containerSize.height)

        case .none:
            ProgressView()
                .tint(.white)
        }
    }

    private var dismissButton: some View {
        VStack {
            HStack {
                Spacer()
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: QIcons.xmark)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(QSpacing.sm)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                }
                .padding(QSpacing.md)
            }
            Spacer()
        }
    }

    private var magnificationGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let proposed = lastScale * value.magnification
                scale = min(max(proposed, 0.5), 10)
            }
            .onEnded { _ in
                withAnimation(QAnimation.springDefault) {
                    scale = min(max(scale, 1), 6)
                    if scale <= 1 {
                        offset = .zero
                    }
                }
                lastScale = min(max(scale, 1), 6)
                if scale <= 1 {
                    lastOffset = .zero
                }
            }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard scale > 1 else { return }
                offset = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                lastOffset = offset
            }
    }

    private func loadFullResolution() async {
        let fetchResult = PHAsset.fetchAssets(
            withLocalIdentifiers: [photo.assetId],
            options: nil
        )
        guard let phAsset = fetchResult.firstObject else { return }
        let targetSize = CGSize(
            width: min(CGFloat(phAsset.pixelWidth), UIScreen.main.bounds.width * UIScreen.main.scale * 2),
            height: min(CGFloat(phAsset.pixelHeight), UIScreen.main.bounds.height * UIScreen.main.scale * 2)
        )
        do {
            let loaded = try await loadHighQualityCGImage(for: phAsset, targetSize: targetSize)
            self.image = loaded
        } catch {
            // fallback: try thumbnail
            let thumb = try? await loadCGImage(for: phAsset, targetSize: QSize.thumbnailRequest)
            self.image = thumb
        }
    }
}
