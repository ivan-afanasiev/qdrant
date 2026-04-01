import SwiftUI

struct GroupComparisonView: View {
    let group: DuplicateGroup
    let selectedKeepId: String?
    let onSelectKeep: (PhotoReference) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text("\(group.count) similar photos")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: gridColumns, spacing: 12) {
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
