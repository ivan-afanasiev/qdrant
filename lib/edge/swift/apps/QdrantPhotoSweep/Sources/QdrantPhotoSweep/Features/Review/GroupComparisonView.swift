import SwiftUI

struct GroupComparisonView: View {
    let group: DuplicateGroup
    let selectedKeepId: String?
    let onSelectKeep: (PhotoReference) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: QSpacing.sm) {
                Text("\(group.count) similar photos")
                    .font(QTypography.bodyMedium)
                    .foregroundStyle(QColors.textTertiary)

                LazyVGrid(columns: gridColumns, spacing: QSpacing.sm) {
                    ForEach(group.photos) { photo in
                        PhotoCardView(
                            photo: photo,
                            isSelected: photo.id == (selectedKeepId ?? group.bestCandidate.id),
                            onTap: { onSelectKeep(photo) }
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
