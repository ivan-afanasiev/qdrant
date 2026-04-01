import SwiftUI

struct SettingsView: View {
    @Environment(\.dependencies) private var dependencies
    @State private var state = SettingsState()

    var body: some View {
        Form {
            thresholdSection
            databaseSection
            aboutSection
        }
        .navigationTitle(L10n.settings)
        .task {
            await loadInfo()
        }
    }

    private var thresholdSection: some View {
        Section {
            VStack(alignment: .leading, spacing: QSpacing.xs) {
                HStack {
                    Text(L10n.similarityThreshold)
                    Spacer()
                    Text(String(format: "%.0f%%", state.similarityThreshold * 100))
                        .monospacedDigit()
                        .foregroundStyle(QColors.textSecondary)
                }
                Slider(value: $state.similarityThreshold, in: 0.7...0.99, step: 0.01)
                    .tint(QColors.primary)
                Text(L10n.thresholdDescription)
                    .font(QTypography.caption)
                    .foregroundStyle(QColors.textTertiary)
            }
        } header: {
            Text(L10n.detection)
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
