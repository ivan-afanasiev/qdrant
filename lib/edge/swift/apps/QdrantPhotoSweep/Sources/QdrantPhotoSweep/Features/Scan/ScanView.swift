import SwiftUI

struct ScanView: View {
    @Environment(\.dependencies) private var dependencies
    @State private var state = ScanState()
    @State private var scanTask: Task<Void, Never>?

    let dateRange: DateRange
    let onComplete: ([DuplicateGroup]) -> Void

    var body: some View {
        VStack(spacing: QSpacing.xl) {
            switch state.status {
            case .idle:
                idleView

            case .scanning(let processed, let total):
                scanningView(processed: processed, total: total)

            case .completed(let indexed):
                completedView(indexed: indexed)

            case .failed(let error):
                failedView(error: error)

            case .cancelled:
                cancelledView
            }
        }
        .padding()
        .navigationTitle(L10n.scanning)
        .navigationBarBackButtonHidden(isScanActive)
        .task {
            startScan()
        }
        .onDisappear {
            scanTask?.cancel()
        }
    }

    private var isScanActive: Bool {
        switch state.status {
        case .scanning: true
        default: false
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
            ZStack {
                Circle()
                    .stroke(lineWidth: QSize.progressStroke)
                    .foregroundStyle(QColors.surfaceMuted)
                Circle()
                    .trim(from: 0, to: state.progress)
                    .stroke(style: StrokeStyle(lineWidth: QSize.progressStroke, lineCap: .round))
                    .foregroundStyle(QColors.primary)
                    .rotationEffect(.degrees(-90))
                    .animation(QAnimation.smooth, value: state.progress)
                VStack {
                    Text("\(Int(state.progress * 100))%")
                        .font(QTypography.numericLarge)
                    Text("\(processed) / \(total)")
                        .font(QTypography.numericSmall)
                        .foregroundStyle(QColors.textTertiary)
                }
            }
            .frame(width: QSize.progressRing, height: QSize.progressRing)

            Text(L10n.embeddingPhotos)
                .font(QTypography.bodyLarge)
            Text(L10n.embeddingSubtitle)
                .font(QTypography.bodyMedium)
                .foregroundStyle(QColors.textTertiary)
                .multilineTextAlignment(.center)

            Button(role: .destructive) {
                scanTask?.cancel()
                state.reduce(.didTapCancel)
            } label: {
                Text(L10n.cancel)
            }
            .buttonStyle(.qDestructive)
        }
    }

    private func completedView(indexed: Int) -> some View {
        VStack(spacing: QSpacing.lg) {
            QStatusIcon(QIcons.successFill, size: QSize.iconXLarge, color: QColors.success)

            Text(L10n.scanComplete)
                .font(QTypography.titleMedium)
            Text(L10n.photosIndexed(indexed))
                .foregroundStyle(QColors.textTertiary)

            Button {
                findDuplicates()
            } label: {
                Label(L10n.findDuplicates, systemImage: QIcons.searchSpark)
            }
            .buttonStyle(.qPrimary)
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
                startScan()
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
                startScan()
            }
            .buttonStyle(.qPrimary)
        }
    }

    private func startScan() {
        guard let deps = dependencies else { return }
        scanTask?.cancel()
        scanTask = Task {
            let pipeline = ScanPipeline(
                photoLibrary: deps.photoLibrary,
                embeddingService: deps.embeddingService,
                vectorStore: deps.vectorStore
            )
            await pipeline.run(dateRange: dateRange, state: state)
        }
    }

    @State private var detectionState = DuplicateDetectionState()

    private func findDuplicates() {
        guard let deps = dependencies else { return }
        Task {
            await detectionState.findDuplicates(
                vectorStore: deps.vectorStore,
                threshold: 0.92
            )
            switch detectionState.status {
            case .complete(let groups):
                onComplete(groups)
            default:
                break
            }
        }
    }
}
