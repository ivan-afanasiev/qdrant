import SwiftUI

struct DateRangePickerView: View {
    @Environment(\.dependencies) private var dependencies
    @State private var state = DateRangePickerState()
    let onStartScan: (DateRange) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
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
        VStack(spacing: 8) {
            Image(systemName: "photo.stack")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("Select Time Range")
                .font(.title2.bold())
            Text("Choose which photos to scan for duplicates")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top)
    }

    private var presetSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Select")
                .font(.headline)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
            ], spacing: 10) {
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
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(presetBackground(for: preset))
                .foregroundStyle(presetForeground(for: preset))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private func presetBackground(for preset: DatePreset) -> some ShapeStyle {
        let isSelected = !state.isCustomRange && state.selectedPreset == preset
        return isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.fill.quaternary)
    }

    private func presetForeground(for preset: DatePreset) -> some ShapeStyle {
        let isSelected = !state.isCustomRange && state.selectedPreset == preset
        return isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary)
    }

    private var customRangeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Custom Range")
                .font(.headline)

            HStack {
                DatePicker("From", selection: $state.customStart, displayedComponents: .date)
                    .labelsHidden()
                Text("to")
                    .foregroundStyle(.secondary)
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
            HStack(spacing: 8) {
                ProgressView()
                Text("Counting photos...")
                    .foregroundStyle(.secondary)
            }
            .padding()

        case .ready(let photoCount):
            HStack {
                Image(systemName: "photo.on.rectangle.angled")
                Text("\(photoCount) photos found")
                    .font(.headline)
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(.fill.quaternary)
            .clipShape(RoundedRectangle(cornerRadius: 12))

        case .failed(let error):
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                Text(error.localizedDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
    }

    private var scanButton: some View {
        Button {
            onStartScan(state.currentDateRange)
        } label: {
            Label("Start Scanning", systemImage: "magnifyingglass")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(.tint)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .disabled(!isScanEnabled)
    }

    private var isScanEnabled: Bool {
        switch state.status {
        case .ready(let count) where count > 0: true
        default: false
        }
    }
}
