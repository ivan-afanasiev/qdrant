import SwiftUI

struct SettingsScanPeriodSectionView: View {
    @Bindable var settings: AppSettings
    var onRescan: () -> Void = {}

    var body: some View {
        Section {
            presetGrid
            customRangeRow

            Button {
                onRescan()
            } label: {
                Label(L10n.settingsRescanButton, systemImage: QIcons.refresh)
            }
            .buttonStyle(.borderless)
            .tint(QColors.primary)
        } header: {
            Text(L10n.settingsScanPeriodHeader)
        } footer: {
            Text(L10n.settingsScanPeriodFooter)
        }
    }

    private var presetGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible()),
        ], spacing: QSpacing.xs) {
            ForEach(DatePreset.allCases) { preset in
                Button {
                    settings.scanPreset = preset
                } label: {
                    Text(preset.localizedName)
                        .font(QTypography.bodyMedium.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, QSpacing.sm)
                        .background(presetBackground(preset))
                        .foregroundStyle(presetForeground(preset))
                        .clipShape(RoundedRectangle(cornerRadius: QRadius.sm))
                }
                .buttonStyle(.plain)
            }
        }
        .listRowInsets(EdgeInsets(top: QSpacing.sm, leading: QSpacing.md, bottom: QSpacing.sm, trailing: QSpacing.md))
    }

    private var customRangeRow: some View {
        VStack(alignment: .leading, spacing: QSpacing.sm) {
            Text(L10n.customRange)
                .font(QTypography.bodyMedium)

            HStack {
                DatePicker(L10n.from, selection: Binding(
                    get: { settings.customRangeStart },
                    set: {
                        settings.customRangeStart = $0
                        settings.isCustomRange = true
                    }
                ), displayedComponents: .date)
                .labelsHidden()

                Text(L10n.to)
                    .foregroundStyle(QColors.textTertiary)

                DatePicker(L10n.toLabel, selection: Binding(
                    get: { settings.customRangeEnd },
                    set: {
                        settings.customRangeEnd = $0
                        settings.isCustomRange = true
                    }
                ), displayedComponents: .date)
                .labelsHidden()
            }
        }
    }

    private func presetBackground(_ preset: DatePreset) -> some ShapeStyle {
        let isSelected = !settings.isCustomRange && settings.scanPreset == preset
        return isSelected ? AnyShapeStyle(QColors.primary) : AnyShapeStyle(QColors.surfaceSubtle)
    }

    private func presetForeground(_ preset: DatePreset) -> some ShapeStyle {
        let isSelected = !settings.isCustomRange && settings.scanPreset == preset
        return isSelected ? AnyShapeStyle(QColors.textOnPrimary) : AnyShapeStyle(QColors.textPrimary)
    }
}
