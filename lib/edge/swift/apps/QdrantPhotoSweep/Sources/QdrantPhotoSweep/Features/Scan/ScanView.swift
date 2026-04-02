import SwiftUI

struct ScanView: View {
    @Environment(\.dependencies) private var dependencies
    @State private var coordinator = ContinuousScanCoordinator()

    let dateRange: DateRange
    let resumeSessionId: UUID?
    let onComplete: () -> Void

    init(dateRange: DateRange, resumeSessionId: UUID? = nil, onComplete: @escaping () -> Void) {
        self.dateRange = dateRange
        self.resumeSessionId = resumeSessionId
        self.onComplete = onComplete
    }

    var body: some View {
        VStack(spacing: QSpacing.xl) {
            switch coordinator.phase {
            case .idle:
                idleView

            case .scanning(let processed, let total):
                scanningView(processed: processed, total: total)

            case .grouping(let progress):
                groupingView(progress: progress)

            case .completed(let groups):
                completedView(groupCount: groups.count)

            case .failed(let error):
                failedView(error: error)

            case .cancelled:
                cancelledView
            }
        }
        .padding()
        .navigationTitle(L10n.scanning)
        .navigationBarBackButtonHidden(coordinator.isActive)
        .task {
            startPipeline()
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .onChange(of: coordinator.isActive) { _, active in
            UIApplication.shared.isIdleTimerDisabled = active
        }
        .onChange(of: coordinator.phase) { _, newPhase in
            if case .completed = newPhase {
                onComplete()
            }
        }
    }

    private var idleView: some View {
        VStack(spacing: QSpacing.md) {
            ProgressView()
            Text(L10n.preparingToScan)
                .foregroundStyle(QColors.textTertiary)
        }
    }

    private func scanningView(processed: Int, total: Int) -> some View {
        VStack(spacing: QSpacing.lg) {
            progressRing(value: coordinator.scanProgress)

            Text(L10n.embeddingPhotos)
                .font(QTypography.bodyLarge)
            Text(L10n.embeddingSubtitle)
                .font(QTypography.bodyMedium)
                .foregroundStyle(QColors.textTertiary)
                .multilineTextAlignment(.center)

            Button(role: .destructive) {
                coordinator.cancel()
            } label: {
                Text(L10n.cancel)
            }
            .buttonStyle(.qDestructive)
        }
    }

    private func groupingView(progress: Double) -> some View {
        VStack(spacing: QSpacing.lg) {
            progressRing(value: progress)

            Text(L10n.findingDuplicates)
                .font(QTypography.bodyLarge)
            Text(L10n.findingDuplicatesSubtitle)
                .font(QTypography.bodyMedium)
                .foregroundStyle(QColors.textTertiary)
                .multilineTextAlignment(.center)
        }
    }

    private func completedView(groupCount: Int) -> some View {
        VStack(spacing: QSpacing.lg) {
            QStatusIcon(QIcons.successFill, size: QSize.iconXLarge, color: QColors.success)

            Text(L10n.scanComplete)
                .font(QTypography.titleMedium)
        }
    }

    private func failedView(error: AppError) -> some View {
        VStack(spacing: QSpacing.md) {
            QStatusIcon(QIcons.warningFill, size: QSize.iconLarge, color: QColors.error)
            Text(L10n.scanFailed)
                .font(QTypography.titleMedium)
            Text(error.localizedDescription)
                .font(QTypography.bodyMedium)
                .foregroundStyle(QColors.textTertiary)
                .multilineTextAlignment(.center)

            Button(L10n.retry) {
                startPipeline()
            }
            .buttonStyle(.qPrimary)
        }
    }

    private var cancelledView: some View {
        VStack(spacing: QSpacing.md) {
            QStatusIcon(QIcons.cancelFill, size: QSize.iconLarge, color: QColors.warning)
            Text(L10n.scanCancelled)
                .font(QTypography.titleMedium)

            Button(L10n.retry) {
                startPipeline()
            }
            .buttonStyle(.qPrimary)
        }
    }

    private func progressRing(value: Double) -> some View {
        ZStack {
            Circle()
                .stroke(lineWidth: QSize.progressStroke)
                .foregroundStyle(QColors.surfaceMuted)
            Circle()
                .trim(from: 0, to: value)
                .stroke(style: StrokeStyle(lineWidth: QSize.progressStroke, lineCap: .round))
                .foregroundStyle(QColors.primary)
                .rotationEffect(.degrees(-90))
                .animation(QAnimation.smooth, value: value)
            VStack {
                Text("\(Int(value * 100))%")
                    .font(QTypography.numericLarge)
            }
        }
        .frame(width: QSize.progressRing, height: QSize.progressRing)
    }

    private func startPipeline() {
        guard !coordinator.isActive else { return }
        guard let deps = dependencies else { return }
        coordinator.startFullPipeline(
            dateRange: dateRange,
            resumeSessionId: resumeSessionId,
            deps: deps
        )
    }
}
