import SwiftUI
import Photos

struct PhotoCardView: View {
    let photo: PhotoReference
    let isSelected: Bool
    let onTap: () -> Void

    @State private var thumbnail: CGImage?

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .bottomLeading) {
                imageContent
                overlayInfo
                selectionBadge
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
            await loadThumbnail()
        }
    }

    @ViewBuilder
    private var imageContent: some View {
        switch thumbnail {
        case .some(let image):
            Image(decorative: image, scale: 1)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(minHeight: QSize.cardImageMinHeight)
                .clipped()

        case .none:
            Rectangle()
                .fill(QColors.surfaceSubtle)
                .frame(height: QSize.cardImageMinHeight)
                .overlay {
                    ProgressView()
                }
        }
    }

    private var overlayInfo: some View {
        VStack(alignment: .leading, spacing: QSpacing.xxxs) {
            Text(photo.resolution)
                .font(QTypography.numericTiny)
            formattedDate
        }
        .padding(QSpacing.xs)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: QRadius.sm))
        .padding(QSpacing.xs)
    }

    @ViewBuilder
    private var formattedDate: some View {
        switch photo.creationDate {
        case .some(let date):
            Text(date, style: .date)
                .font(QTypography.captionSmall)
        case .none:
            Text("Unknown date")
                .font(QTypography.captionSmall)
                .foregroundStyle(QColors.textTertiary)
        }
    }

    @ViewBuilder
    private var selectionBadge: some View {
        switch isSelected {
        case true:
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
        case false:
            EmptyView()
        }
    }

    private func loadThumbnail() async {
        let fetchResult = PHAsset.fetchAssets(
            withLocalIdentifiers: [photo.assetId],
            options: nil
        )
        guard let phAsset = fetchResult.firstObject else { return }
        do {
            let image = try await loadCGImage(
                for: phAsset,
                targetSize: QSize.thumbnailRequest
            )
            self.thumbnail = image
        } catch {
            // Thumbnail loading is best-effort
        }
    }
}
