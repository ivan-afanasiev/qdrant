import SwiftUI

struct SettingsDatabaseSectionView: View {
    @Environment(\.dependencies) private var dependencies
    @State private var state = SettingsState()

    private var useCases: SettingsFeature.UseCases? {
        dependencies?.settingsUseCases
    }

    var body: some View {
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
                Label(error.localizedDescription, systemImage: QIcons.warningFill)
                    .foregroundStyle(QColors.error)
                    .font(QTypography.caption)
            }
        } header: {
            Text(L10n.database)
        }
        .task { await loadInfo() }
    }

    private func loadInfo() async {
        guard let useCases else { return }
        do {
            let output = try await useCases.loadDatabaseInfo.execute(())
            state.reduce(.didLoadInfo(pointCount: output.pointCount))
        } catch {
            state.reduce(.didFail(error as? AppError ?? .unknown(error.localizedDescription)))
        }
    }

    private func clearDatabase() {
        guard let useCases else { return }
        state.reduce(.didTapClearDatabase)
        Task {
            do {
                try await useCases.clearDatabase.execute(())
                state.reduce(.didFinishClearing)
            } catch {
                state.reduce(.didFail(error as? AppError ?? .unknown(error.localizedDescription)))
            }
        }
    }
}
