import SwiftUI

struct DateRangePickerView: View {
    @Environment(\.dependencies) private var dependencies
    @State private var state = DateRangePickerState()
    let onStartScan: (DateRange) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: QSpacing.xl) {
                headerSection
                presetSection
                customRangeSection
                statusSection
                scanButton
            }
            .padding()
        }
        .navigationTitle("Qdrant PhotoSweep")
        .task {
            guard let deps = dependencies else { return }
            await state.loadCount(using: deps.photoLibrary)
        }
    }

    private var headerSection: some View {
        VStack(spacing: QSpacing.xs) {
            QStatusIcon(QIcons.photoStack, size: QSize.iconLarge, color: QColors.primary)
            Text("Select Time Range")
                .font(QTypography.titleMedium)
            Text("Choose which photos to scan for duplicates")
                .font(QTypography.bodyMedium)
                .foregroundStyle(QColors.textTertiary)
        }
        .padding(.top)
    }

    private var presetSection: some View {
        VStack(alignment: .leading, spacing: QSpacing.sm) {
            Text("Quick Select")
                .font(QTypography.bodyLarge)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
            ], spacing: QSpacing.xs) {
                ForEach(DatePreset.allCases) { preset in
                    presetButton(preset)
                }
            }
        }
    }

    private func presetButton(_ preset: DatePreset) -> some View {
        Button {
            state.reduce(.presetSelected(preset))
            Task {
                guard let deps = dependencies else { return }
                await state.recount(using: deps.photoLibrary)
            }
        } label: {
            Text(preset.rawValue)
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
            Text("Custom Range")
                .font(QTypography.bodyLarge)

            HStack {
                DatePicker("From", selection: $state.customStart, displayedComponents: .date)
                    .labelsHidden()
                Text("to")
                    .foregroundStyle(QColors.textTertiary)
                DatePicker("To", selection: $state.customEnd, displayedComponents: .date)
                    .labelsHidden()
            }
            .onChange(of: state.customStart) { _, newValue in
                state.reduce(.customRangeChanged(start: newValue, end: state.customEnd))
                Task {
                    guard let deps = dependencies else { return }
                    await state.recount(using: deps.photoLibrary)
                }
            }
            .onChange(of: state.customEnd) { _, newValue in
                state.reduce(.customRangeChanged(start: state.customStart, end: newValue))
                Task {
                    guard let deps = dependencies else { return }
                    await state.recount(using: deps.photoLibrary)
                }
            }
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        switch state.status {
        case .idle:
            EmptyView()

        case .counting:
            HStack(spacing: QSpacing.xs) {
                ProgressView()
                Text("Counting photos...")
                    .foregroundStyle(QColors.textTertiary)
            }
            .padding()

        case .ready(let photoCount):
            HStack {
                Image(systemName: QIcons.photoAngled)
                    .foregroundStyle(QColors.primary)
                Text("\(photoCount) photos found")
                    .font(QTypography.bodyLarge)
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(QColors.surfaceSubtle)
            .clipShape(RoundedRectangle(cornerRadius: QRadius.md))

        case .failed(let error):
            VStack(spacing: QSpacing.xs) {
                Image(systemName: QIcons.warning)
                    .foregroundStyle(QColors.error)
                Text(error.localizedDescription)
                    .font(QTypography.caption)
                    .foregroundStyle(QColors.textTertiary)
            }
            .padding()
        }
    }

    private var scanButton: some View {
        Button {
            onStartScan(state.currentDateRange)
        } label: {
            Label("Start Scanning", systemImage: QIcons.search)
        }
        .buttonStyle(.qPrimary)
        .disabled(!isScanEnabled)
    }

    private var isScanEnabled: Bool {
        switch state.status {
        case .ready(let count) where count > 0: true
        default: false
        }
    }
}
