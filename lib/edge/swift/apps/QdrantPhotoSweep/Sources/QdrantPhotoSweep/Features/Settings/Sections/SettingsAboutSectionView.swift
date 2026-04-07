import SwiftUI

struct SettingsAboutSectionView: View {
    var body: some View {
        Section {
            HStack {
                Text(L10n.engine)
                Spacer()
                Text(L10n.qdrantEdge)
                    .foregroundStyle(QColors.textSecondary)
            }
            HStack {
                Text(L10n.embeddings)
                Spacer()
                Text(L10n.appleVision)
                    .foregroundStyle(QColors.textSecondary)
            }
        } header: {
            Text(L10n.about)
        }
    }
}
