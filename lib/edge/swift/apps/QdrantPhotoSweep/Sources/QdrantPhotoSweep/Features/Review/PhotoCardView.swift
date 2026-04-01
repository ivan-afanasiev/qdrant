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
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? Color.green : Color.clear, lineWidth: 3)
            )
            .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
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
                .frame(minHeight: 200)
                .clipped()

        case .none:
            Rectangle()
                .fill(.fill.quaternary)
                .frame(height: 200)
                .overlay {
                    ProgressView()
                }
        }
    }

    private var overlayInfo: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(photo.resolution)
                .font(.caption2.bold().monospacedDigit())
            formattedDate
        }
        .padding(8)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(8)
    }

    @ViewBuilder
    private var formattedDate: some View {
        switch photo.creationDate {
        case .some(let date):
            Text(date, style: .date)
                .font(.caption2)
        case .none:
            Text("Unknown date")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var selectionBadge: some View {
        switch isSelected {
        case true:
            VStack {
                HStack {
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.green)
                        .padding(8)
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
                targetSize: CGSize(width: 300, height: 300)
            )
            self.thumbnail = image
        } catch {
            // Thumbnail loading is best-effort
        }
    }
}
