import SwiftUI

struct SettingsDetectionSectionView: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: QSpacing.xs) {
                HStack {
                    Text(L10n.similarityThreshold)
                    Spacer()
                    Text(String(format: "%.0f%%", settings.similarityThreshold * 100))
                        .monospacedDigit()
                        .foregroundStyle(QColors.textSecondary)
                }
                Slider(value: $settings.similarityThreshold, in: 0.7...0.99, step: 0.01)
                    .tint(QColors.primary)
                Text(L10n.thresholdDescription)
                    .font(QTypography.caption)
                    .foregroundStyle(QColors.textTertiary)
            }
        } header: {
            Text(L10n.detection)
        }
    }
}
