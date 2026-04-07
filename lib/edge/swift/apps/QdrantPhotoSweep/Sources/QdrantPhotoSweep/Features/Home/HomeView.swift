import SwiftUI

struct HomeView: View {
    @Environment(\.dependencies) private var dependencies
    @State private var state = HomeState()

    let onStartScan: (DateRange) -> Void
    let onResumeScan: (DateRange, UUID) -> Void
    let onReviewPending: () -> Void

    private var useCases: HomeFeature.UseCases? {
        dependencies?.homeUseCases
    }

    var body: some View {
        ScrollView {
            VStack(spacing: QSpacing.xl) {
                bannersSection
                statsSection
                startScanButton
            }
            .padding()
        }
        .navigationTitle(L10n.appTitle)
        .task { await loadData() }
    }

    // MARK: - Actions

    private func loadData() async {
        guard let useCases else { return }
        do {
            let output = try await useCases.loadHomeData.execute(())
            state.reduce(.didLoadData(output))
        } catch {
            AppLog.home.error("Failed to load home data: \(error)")
        }
    }

    // MARK: - Banners

    @ViewBuilder
    private var bannersSection: some View {
        if let session = state.interruptedSession {
            let remaining = session.totalPhotos - session.indexedPhotos
            BannerCard(
                icon: QIcons.warningFill,
                iconColor: QColors.warning,
                message: L10n.interruptedScanBanner(remaining),
                buttonTitle: L10n.resumeScan,
                buttonIcon: QIcons.search,
                buttonStyle: .primary
            ) {
                let range = DateRange(start: session.rangeStart, end: session.rangeEnd)
                onResumeScan(range, session.id)
            }
        }

        if state.newPhotoCount > 0, let session = state.lastSession {
            BannerCard(
                icon: QIcons.sparkles,
                iconColor: QColors.primary,
                message: L10n.newPhotosSinceLastScan(state.newPhotoCount),
                buttonTitle: L10n.scanNewPhotos,
                buttonIcon: QIcons.search,
                buttonStyle: .secondary
            ) {
                let incrementalRange = DateRange(start: session.scannedAt, end: .now)
                onStartScan(incrementalRange)
            }
        }

        if state.pendingGroupCount > 0 {
            BannerCard(
                icon: QIcons.photoStack,
                iconColor: QColors.warning,
                message: L10n.pendingGroupsToReview(state.pendingGroupCount),
                buttonTitle: L10n.continueReview,
                buttonIcon: QIcons.photoAngled,
                buttonStyle: .secondary
            ) {
                onReviewPending()
            }
        }
    }

    // MARK: - Statistics

    private var statsSection: some View {
        VStack(spacing: QSpacing.sm) {
            Text(L10n.homeStatsHeader)
                .font(QTypography.bodyLarge)
                .frame(maxWidth: .infinity, alignment: .leading)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
            ], spacing: QSpacing.sm) {
                StatCard(
                    icon: QIcons.photoStackFill,
                    value: "\(state.stats.totalPhotosIndexed)",
                    label: L10n.homeStatPhotosIndexed
                )

                StatCard(
                    icon: QIcons.clock,
                    value: formattedLastScan,
                    label: L10n.homeStatLastScan
                )

                StatCard(
                    icon: QIcons.stackFill,
                    value: "\(state.stats.duplicateGroupsFound)",
                    label: L10n.homeStatDuplicatesFound
                )

                StatCard(
                    icon: QIcons.trashFill,
                    value: "\(state.stats.photosDeleted)",
                    label: L10n.homeStatPhotosDeleted
                )
            }
        }
    }

    private var formattedLastScan: String {
        guard let date = state.stats.lastScanDate else { return "—" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: .now)
    }

    // MARK: - Start Scan

    private var startScanButton: some View {
        VStack(spacing: QSpacing.sm) {
            Button {
                guard let deps = dependencies else { return }
                onStartScan(deps.settings.currentDateRange)
            } label: {
                Label(L10n.startScanning, systemImage: QIcons.search)
            }
            .buttonStyle(.qPrimary)
        }
    }
}
