import SwiftUI

struct OnboardingScanPeriodStep: View {
    var state: OnboardingState

    var body: some View {
        VStack(spacing: QSpacing.xxl) {
            Spacer()

            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 72))
                .foregroundStyle(QColors.primary)

            VStack(spacing: QSpacing.sm) {
                Text(L10n.onboardingScanPeriodTitle)
                    .font(QTypography.titleLarge)
                    .multilineTextAlignment(.center)

                Text(L10n.onboardingScanPeriodSubtitle)
                    .font(QTypography.bodyMedium)
                    .foregroundStyle(QColors.textSecondary)
                    .multilineTextAlignment(.center)
            }

            presetGrid

            customRangeSection

            Spacer()
        }
        .padding()
    }

    private var presetGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible()),
        ], spacing: QSpacing.xs) {
            ForEach(DatePreset.allCases) { preset in
                presetButton(preset)
            }
        }
    }

    private func presetButton(_ preset: DatePreset) -> some View {
        Button {
            state.reduce(.didSelectPreset(preset))
        } label: {
            Text(preset.localizedName)
                .font(QTypography.bodyMedium.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, QSpacing.sm)
                .background(presetBackground(for: preset))
                .foregroundStyle(presetForeground(for: preset))
                .clipShape(RoundedRectangle(cornerRadius: QRadius.sm))
        }
    }

    private func presetBackground(for preset: DatePreset) -> some ShapeStyle {
        let isSelected = !state.isCustomRange && state.selectedPreset == preset
        return isSelected ? AnyShapeStyle(QColors.primary) : AnyShapeStyle(QColors.surfaceSubtle)
    }

    private func presetForeground(for preset: DatePreset) -> some ShapeStyle {
        let isSelected = !state.isCustomRange && state.selectedPreset == preset
        return isSelected ? AnyShapeStyle(QColors.textOnPrimary) : AnyShapeStyle(QColors.textPrimary)
    }

    private var customRangeSection: some View {
        VStack(alignment: .leading, spacing: QSpacing.sm) {
            Text(L10n.customRange)
                .font(QTypography.bodyLarge)

            HStack {
                DatePicker(L10n.from, selection: Binding(
                    get: { state.customRangeStart },
                    set: { state.reduce(.didSetCustomRange(start: $0, end: state.customRangeEnd)) }
                ), displayedComponents: .date)
                .labelsHidden()

                Text(L10n.to)
                    .foregroundStyle(QColors.textTertiary)

                DatePicker(L10n.toLabel, selection: Binding(
                    get: { state.customRangeEnd },
                    set: { state.reduce(.didSetCustomRange(start: state.customRangeStart, end: $0)) }
                ), displayedComponents: .date)
                .labelsHidden()
            }
        }
    }
}
