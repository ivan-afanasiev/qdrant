import SwiftUI

struct SettingsView: View {
    @Environment(\.dependencies) private var dependencies
    @Environment(\.dismiss) private var dismiss
    @State private var stats = ScanStats()

    var body: some View {
        Form {
            SettingsStatsSectionView(stats: stats)

            if let settings = dependencies?.settings {
                SettingsScanPeriodSectionView(settings: settings) {
                    settings.requestRescan()
                    dismiss()
                }
                SettingsDetectionSectionView(settings: settings)
            }

            SettingsDatabaseSectionView()
            SettingsAboutSectionView()
        }
        .navigationTitle(L10n.settings)
        .task { await loadStats() }
    }

    private func loadStats() async {
        guard let useCases = dependencies?.settingsUseCases else { return }
        do {
            stats = try await useCases.loadStats.execute(())
        } catch {
            AppLog.settings.error("Failed to load stats: \(error)")
        }
    }
}
