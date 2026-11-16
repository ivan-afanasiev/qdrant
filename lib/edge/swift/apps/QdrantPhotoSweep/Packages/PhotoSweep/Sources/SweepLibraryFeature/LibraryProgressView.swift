#if os(iOS)
import SwiftUI
import SweepDesignSystem
import SweepDomain
import SweepFeatureState

/// Vectorization progress with the single control the status offers. There is no Cancel.
public struct LibraryProgressView: View {
    private let store: Store<LibraryFeature>
    private let isCompact: Bool

    /// - Parameter isCompact: a one-line status for showing above review cards.
    public init(store: Store<LibraryFeature>, isCompact: Bool = false) {
        self.store = store
        self.isCompact = isCompact
    }

    public var body: some View {
        Group {
            if isCompact {
                compact
            } else {
                full
            }
        }
        .task { store.send(.onAppear) }
        .onDisappear { store.send(.onDisappear) }
    }

    private var full: some View {
        VStack(spacing: QSpacing.lg) {
            VStack(spacing: QSpacing.sm) {
                Text(L10n.libraryTitle)
                    .font(QTypography.titleLarge)
                Text(L10n.librarySubtitle)
                    .font(QTypography.bodyMedium)
                    .foregroundStyle(QColors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            VStack(spacing: QSpacing.md) {
                statusLine
                if let progress = store.state.status.progress, progress.total > 0 {
                    ProgressView(value: Double(progress.vectorized + progress.deferred), total: Double(progress.total))
                        .tint(QColors.primary)
                    Text(L10n.scanProgressStatus(progress.vectorized + progress.deferred, progress.total))
                        .font(QTypography.numericSmall)
                        .foregroundStyle(QColors.textSecondary)
                    if progress.deferred > 0 {
                        Text(L10n.libraryUnavailable(progress.deferred))
                            .font(QTypography.bodySmall)
                            .foregroundStyle(QColors.warning)
                    }
                }
                controlButton
            }
            .qGlassPanel()
        }
        .padding(QSpacing.lg)
    }

    private var compact: some View {
        HStack(spacing: QSpacing.sm) {
            statusLine
            Spacer()
            controlButton
        }
        .qGlassPanel(cornerRadius: QRadius.pill)
    }

    @ViewBuilder
    private var statusLine: some View {
        switch store.state.status {
        case .idle:
            Text(L10n.libraryIdle)
        case .running(let progress):
            Label {
                Text(L10n.scanProgressStatus(progress.vectorized + progress.deferred, progress.total))
                    .monospacedDigit()
            } icon: {
                ProgressView()
            }
        case .pausedByUser:
            Label { Text(L10n.libraryPaused) } icon: { Image(systemName: "pause.circle") }
        case .interrupted:
            Text(L10n.libraryInterrupted)
                .foregroundStyle(QColors.textSecondary)
        case .failed(.authorization, _):
            Label { Text(L10n.libraryFailedAuthorization) } icon: { Image(systemName: QIcons.warning) }
                .foregroundStyle(QColors.error)
        case .failed:
            Label { Text(L10n.libraryFailedOther) } icon: { Image(systemName: QIcons.warning) }
                .foregroundStyle(QColors.error)
        case .completed(let deferred):
            VStack(spacing: QSpacing.xxs) {
                Label { Text(L10n.libraryCompleted) } icon: { Image(systemName: QIcons.success) }
                    .foregroundStyle(QColors.success)
                if deferred > 0 {
                    Text(L10n.libraryUnavailable(deferred))
                        .font(QTypography.bodySmall)
                        .foregroundStyle(QColors.warning)
                }
            }
        }
    }

    @ViewBuilder
    private var controlButton: some View {
        if let control = store.state.control {
            Button {
                store.send(.controlTapped(control))
            } label: {
                switch control {
                case .pause: Text(L10n.pause)
                case .resume: Text(L10n.resume)
                case .retry: Text(L10n.retry)
                }
            }
            .buttonStyle(.glass)
        }
    }
}

extension VectorizationStatus {
    /// Progress for statuses that carry it.
    var progress: VectorizationProgress? {
        switch self {
        case .running(let progress), .pausedByUser(let progress), .interrupted(let progress), .failed(_, let progress):
            progress
        case .idle, .completed:
            nil
        }
    }
}
#endif
