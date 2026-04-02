import SwiftUI

struct SettingsView: View {
    @Environment(\.dependencies) private var dependencies
    @State private var state = SettingsState()

    var body: some View {
        Form {
            scanPeriodSection
            thresholdSection
            databaseSection
            aboutSection
        }
        .navigationTitle(L10n.settings)
        .task {
            await loadInfo()
        }
    }

    // MARK: - Scan Period

    @ViewBuilder
    private var scanPeriodSection: some View {
        if let settings = dependencies?.settings {
            Section {
                presetGrid(settings: settings)
                customRangeRow(settings: settings)
            } header: {
                Text(L10n.settingsScanPeriodHeader)
            } footer: {
                Text(L10n.settingsScanPeriodFooter)
            }
        }
    }

    private func presetGrid(settings: AppSettings) -> some View {
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
                        .background(presetBg(for: preset, settings: settings))
                        .foregroundStyle(presetFg(for: preset, settings: settings))
                        .clipShape(RoundedRectangle(cornerRadius: QRadius.sm))
                }
                .buttonStyle(.plain)
            }
        }
        .listRowInsets(EdgeInsets(top: QSpacing.sm, leading: QSpacing.md, bottom: QSpacing.sm, trailing: QSpacing.md))
    }

    private func presetBg(for preset: DatePreset, settings: AppSettings) -> some ShapeStyle {
        let isSelected = !settings.isCustomRange && settings.scanPreset == preset
        return isSelected ? AnyShapeStyle(QColors.primary) : AnyShapeStyle(QColors.surfaceSubtle)
    }

    private func presetFg(for preset: DatePreset, settings: AppSettings) -> some ShapeStyle {
        let isSelected = !settings.isCustomRange && settings.scanPreset == preset
        return isSelected ? AnyShapeStyle(QColors.textOnPrimary) : AnyShapeStyle(QColors.textPrimary)
    }

    private func customRangeRow(settings: AppSettings) -> some View {
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

    // MARK: - Detection

    @ViewBuilder
    private var thresholdSection: some View {
        switch dependencies?.settings {
        case .some(let settings):
            Section {
                ThresholdSlider(settings: settings)
            } header: {
                Text(L10n.detection)
            }
        case .none:
            EmptyView()
        }
    }

    @ViewBuilder
    private var databaseSection: some View {
        Section {
            switch state.status {
            case .idle(let count):
                HStack {
                    Text(L10n.indexedPhotos)
                    Spacer()
                    Text("\(count)")
                        .foregroundStyle(QColors.textSecondary)
                        .monospacedDigit()
                }

                Button(role: .destructive) {
                    clearDatabase()
                } label: {
                    Label(L10n.clearDatabase, systemImage: QIcons.delete)
                }
                .buttonStyle(.borderless)
                .disabled(count == 0)

            case .clearing:
                HStack {
                    ProgressView()
                    Text(L10n.clearing)
                        .foregroundStyle(QColors.textTertiary)
                }

            case .cleared:
                Label(L10n.databaseCleared, systemImage: QIcons.success)
                    .foregroundStyle(QColors.success)

            case .failed(let error):
                Label(error.localizedDescription, systemImage: QIcons.warning)
                    .foregroundStyle(QColors.error)
                    .font(QTypography.caption)
            }
        } header: {
            Text(L10n.database)
        }
    }

    private var aboutSection: some View {
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

    private func loadInfo() async {
        guard let deps = dependencies else { return }
        do {
            let count = try await deps.vectorStore.count()
            state.reduce(.didLoadInfo(pointCount: count))
        } catch {
            state.reduce(.didFail(error))
        }
    }

    private func clearDatabase() {
        guard let deps = dependencies else { return }
        state.reduce(.didTapClearDatabase)
        Task {
            do {
                var offset: String? = nil
                while true {
                    let page = try await deps.vectorStore.scroll(offset: offset, limit: 100)
                    guard !page.records.isEmpty else { break }
                    let ids = page.records.map(\.id)
                    try await deps.vectorStore.delete(ids: ids)
                    offset = page.nextOffset
                    guard offset != nil else { break }
                }
                state.reduce(.didFinishClearing)
            } catch let error as AppError {
                state.reduce(.didFail(error))
            } catch {
                state.reduce(.didFail(.unknown(error.localizedDescription)))
            }
        }
    }
}

private struct ThresholdSlider: View {
    @Bindable var settings: AppSettings

    var body: some View {
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
    }
}
