import SwiftUI

struct SettingsStatsSectionView: View {
    let stats: ScanStats

    var body: some View {
        Section {
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
            ], spacing: QSpacing.sm) {
                StatCell(
                    icon: QIcons.photoStackFill,
                    value: "\(stats.totalPhotosIndexed)",
                    label: L10n.settingsStatPhotosIndexed
                )
                StatCell(
                    icon: QIcons.clock,
                    value: formattedLastScan,
                    label: L10n.settingsStatLastScan
                )
                StatCell(
                    icon: QIcons.stackFill,
                    value: "\(stats.duplicateGroupsFound)",
                    label: L10n.settingsStatDuplicatesFound
                )
                StatCell(
                    icon: QIcons.trashFill,
                    value: "\(stats.photosDeleted)",
                    label: L10n.settingsStatPhotosDeleted
                )
            }
            .listRowInsets(EdgeInsets(top: QSpacing.sm, leading: QSpacing.md, bottom: QSpacing.sm, trailing: QSpacing.md))
        } header: {
            Text(L10n.settingsStatHeader)
        }
    }

    private var formattedLastScan: String {
        guard let date = stats.lastScanDate else { return "—" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: .now)
    }
}

private struct StatCell: View {
    let icon: String
    let value: String
    let label: LocalizedStringKey

    var body: some View {
        VStack(spacing: QSpacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(QColors.primary)
            Text(value)
                .font(QTypography.numericLarge)
            Text(label)
                .font(QTypography.caption)
                .foregroundStyle(QColors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, QSpacing.lg)
        .background(QColors.surfaceSubtle)
        .clipShape(RoundedRectangle(cornerRadius: QRadius.md))
    }
}
