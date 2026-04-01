import SwiftUI

struct GroupComparisonView: View {
    let group: DuplicateGroup
    let keptIds: Set<String>
    let onToggleKeep: (PhotoReference) -> Void
    let onFullscreen: (PhotoReference) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: QSpacing.sm) {
                Text(L10n.similarPhotos(group.count))
                    .font(QTypography.bodyMedium)
                    .foregroundStyle(QColors.textTertiary)

                LazyVGrid(columns: gridColumns, spacing: QSpacing.sm) {
                    ForEach(group.photos) { photo in
                        PhotoCardView(
                            photo: photo,
                            isSelected: keptIds.contains(photo.id),
                            onTap: { onToggleKeep(photo) },
                            onFullscreen: { onFullscreen(photo) }
                        )
                    }
                }
            }
            .padding()
        }
    }

    private var gridColumns: [GridItem] {
        switch group.count {
        case 1...2:
            [GridItem(.flexible())]
        default:
            [GridItem(.flexible()), GridItem(.flexible())]
        }
    }
}
