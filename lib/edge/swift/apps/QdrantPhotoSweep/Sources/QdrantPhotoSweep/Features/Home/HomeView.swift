import SwiftUI

struct HomeView: View {
    @Environment(\.dependencies) private var dependencies
    @State private var state = HomeState()

    let onStartScan: (DateRange) -> Void
    let onResumeScan: (DateRange, UUID) -> Void
    let onReviewPending: () -> Void

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
        .task {
            guard let deps = dependencies else { return }
            await state.loadData(scanStore: deps.scanStore, photoLibrary: deps.photoLibrary)
        }
    }

    // MARK: - Banners

    @ViewBuilder
    private var bannersSection: some View {
        if let session = state.interruptedSession {
            interruptedScanBanner(session: session)
        }

        if state.groupingInterruptedSession != nil {
            groupingInterruptedBanner
        }

        if state.newPhotoCount > 0, let session = state.lastSession {
            newPhotosBanner(newCount: state.newPhotoCount, session: session)
        }

        if state.pendingGroupCount > 0 {
            pendingGroupsBanner
        }
    }

    private func interruptedScanBanner(session: ScanSessionDTO) -> some View {
        let remaining = session.totalPhotos - session.indexedPhotos
        return VStack(spacing: QSpacing.sm) {
            HStack(spacing: QSpacing.sm) {
                Image(systemName: QIcons.warningFill)
                    .foregroundStyle(QColors.warning)
                Text(L10n.interruptedScanBanner(remaining))
                    .font(QTypography.bodyMedium)
                Spacer()
            }

            Button {
                let range = DateRange(start: session.rangeStart, end: session.rangeEnd)
                onResumeScan(range, session.id)
            } label: {
                Label(L10n.resumeScan, systemImage: QIcons.search)
            }
            .buttonStyle(.qPrimary)
        }
        .padding()
        .background(QColors.surfaceSubtle)
        .clipShape(RoundedRectangle(cornerRadius: QRadius.md))
    }

    private var groupingInterruptedBanner: some View {
        VStack(spacing: QSpacing.sm) {
            HStack(spacing: QSpacing.sm) {
                Image(systemName: QIcons.warningFill)
                    .foregroundStyle(QColors.warning)
                Text(L10n.groupingInterruptedBanner)
                    .font(QTypography.bodyMedium)
                Spacer()
            }

            Button {
                onReviewPending()
            } label: {
                Label(L10n.resumeGrouping, systemImage: QIcons.search)
            }
            .buttonStyle(.qPrimary)
        }
        .padding()
        .background(QColors.surfaceSubtle)
        .clipShape(RoundedRectangle(cornerRadius: QRadius.md))
    }

    private func newPhotosBanner(newCount: Int, session: ScanSessionDTO) -> some View {
        VStack(spacing: QSpacing.sm) {
            HStack(spacing: QSpacing.sm) {
                Image(systemName: QIcons.sparkles)
                    .foregroundStyle(QColors.primary)
                Text(L10n.newPhotosSinceLastScan(newCount))
                    .font(QTypography.bodyMedium)
                Spacer()
            }

            Button {
                let incrementalRange = DateRange(start: session.scannedAt, end: .now)
                onStartScan(incrementalRange)
            } label: {
                Label(L10n.scanNewPhotos, systemImage: QIcons.search)
            }
            .buttonStyle(.qSecondary)
        }
        .padding()
        .background(QColors.surfaceSubtle)
        .clipShape(RoundedRectangle(cornerRadius: QRadius.md))
    }

    private var pendingGroupsBanner: some View {
        VStack(spacing: QSpacing.sm) {
            HStack(spacing: QSpacing.sm) {
                Image(systemName: QIcons.photoStack)
                    .foregroundStyle(QColors.warning)
                Text(L10n.pendingGroupsToReview(state.pendingGroupCount))
                    .font(QTypography.bodyMedium)
                Spacer()
            }

            Button {
                onReviewPending()
            } label: {
                Label(L10n.continueReview, systemImage: QIcons.photoAngled)
            }
            .buttonStyle(.qSecondary)
        }
        .padding()
        .background(QColors.surfaceSubtle)
        .clipShape(RoundedRectangle(cornerRadius: QRadius.md))
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
                    icon: "photo.stack.fill",
                    value: "\(state.stats.totalPhotosIndexed)",
                    label: L10n.homeStatPhotosIndexed
                )

                StatCard(
                    icon: "clock.fill",
                    value: formattedLastScan,
                    label: L10n.homeStatLastScan
                )

                StatCard(
                    icon: "square.stack.3d.up.fill",
                    value: "\(state.stats.duplicateGroupsFound)",
                    label: L10n.homeStatDuplicatesFound
                )

                StatCard(
                    icon: "trash.fill",
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

    // MARK: - Action

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
