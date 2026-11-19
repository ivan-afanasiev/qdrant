#if os(iOS)
import SwiftUI
import SweepDesignSystem
import SweepDomain
import SweepFeatureState

/// Vectorization progress with the single control the status offers. There is no Cancel.
/// The owner of `store` starts and stops status observation (`.onAppear` / `.onDisappear`),
/// so that status stays current while this view is hidden or replaced.
public struct LibraryProgressView: View {
    private let store: Store<LibraryFeature>
    private let isCompact: Bool
    private let loadThumbnails: @Sendable () async -> [CGImage]
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showAnimation: Bool = false
    @State private var headerHeight: CGFloat = 350

    /// - Parameter isCompact: a one-line status for showing above review cards.
    public init(
        store: Store<LibraryFeature>,
        isCompact: Bool = false,
        loadThumbnails: @escaping @Sendable () async -> [CGImage] = { [] }
    ) {
        self.store = store
        self.isCompact = isCompact
        self.loadThumbnails = loadThumbnails
    }

    public var body: some View {
        if isCompact {
            compact
        } else {
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                            .frame(height: showAnimation ? 0 : max(0, (geometry.size.height - headerHeight) / 2))
                        full
                            .onGeometryChange(for: CGFloat.self) { proxy in
                                proxy.size.height
                            } action: { height in
                                headerHeight = height
                            }
                        if showAnimation {
                            ProgressPhotoAnimation(
                                isRunning: isProcessing && scenePhase == .active,
                                loadThumbnails: loadThumbnails
                            )
                            .frame(height: max(220, geometry.size.height - headerHeight))
                            .transition(.opacity)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .task(id: isProcessing && scenePhase == .active) {
                    guard isProcessing, scenePhase == .active, !showAnimation else { return }
                    do {
                        try await Task.sleep(for: .seconds(5))
                        withAnimation(reduceMotion ? nil : .smooth(duration: 0.7)) {
                            showAnimation = true
                        }
                    } catch { }
                }
            }
        }
    }

    private var isProcessing: Bool {
        switch store.state.status {
        case .preparing, .running: true
        default: false
        }
    }

    private var full: some View {
        VStack(spacing: QSpacing.lg) {
            VStack(spacing: QSpacing.sm) {
                Text(L10n.libraryTitle)
                    .font(showAnimation ? QTypography.titleMedium : QTypography.titleLarge)
                Text(L10n.librarySubtitle)
                    .font(QTypography.bodyMedium)
                    .foregroundStyle(QColors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            VStack(spacing: QSpacing.md) {
                statusLine
                if case .preparing(let done, let total) = store.state.status, total > 0 {
                    ProgressView(value: Double(done), total: Double(total))
                        .tint(QColors.primary)
                } else if let progress = store.state.status.progress, progress.total > 0 {
                    let done = Double(progress.vectorized + progress.deferred)
                    ProgressView(value: done, total: Double(progress.total))
                        .tint(QColors.primary)
                    Group {
                        // The status line already shows the count while running.
                        if case .running = store.state.status {
                            Text(done / Double(progress.total), format: .percent.precision(.fractionLength(0)))
                        } else {
                            Text(L10n.scanProgressStatus(progress.vectorized + progress.deferred, progress.total))
                        }
                    }
                    .font(QTypography.numericSmall)
                    .foregroundStyle(QColors.textSecondary)
                    if progress.deferred > 0 {
                        Text(L10n.libraryUnavailable(progress.deferred))
                            .font(QTypography.bodySmall)
                            .foregroundStyle(QColors.warning)
                    }
                }
                controlButton(isLarge: true)
            }
            .qGlassPanel()
        }
        .padding(QSpacing.lg)
    }

    private var compact: some View {
        HStack(spacing: QSpacing.sm) {
            statusLine
            Spacer()
            controlButton(isLarge: false)
        }
        .qGlassPanel(cornerRadius: QRadius.pill)
    }

    @ViewBuilder
    private var statusLine: some View {
        switch store.state.status {
        case .idle:
            Text(L10n.libraryIdle)
        case .preparing(let done, let total):
            Label {
                if total > 0 {
                    Text(L10n.libraryPreparing(done, total)).monospacedDigit()
                } else {
                    Text(L10n.libraryPreparingStart)
                }
            } icon: {
                ProgressView()
            }
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

    /// - Parameter isLarge: full-width large button matching onboarding and review controls;
    ///   the compact line above the cards keeps a small one.
    @ViewBuilder
    private func controlButton(isLarge: Bool) -> some View {
        if let control = store.state.control {
            let button = Button {
                store.send(.controlTapped(control))
            } label: {
                Group {
                    switch control {
                    case .pause: Text(L10n.pause)
                    case .resume: Text(L10n.resume)
                    case .retry: Text(L10n.retry)
                    }
                }
                .frame(maxWidth: isLarge ? .infinity : nil)
            }
            .controlSize(isLarge ? .large : .regular)
            // Resume and Retry are the main action; Pause is secondary.
            if control == .pause {
                button.buttonStyle(.glass)
            } else {
                button.buttonStyle(.glassProminent).tint(QColors.primary)
            }
        }
    }
}

extension VectorizationStatus {
    /// Progress for statuses that carry it.
    var progress: VectorizationProgress? {
        switch self {
        case .running(let progress), .pausedByUser(let progress), .interrupted(let progress), .failed(_, let progress):
            progress
        case .idle, .preparing, .completed:
            nil
        }
    }
}

/// Decorative pairs illustrate processing; they do not represent discovered matches.
private struct ProgressPhotoAnimation: View {
    let isRunning: Bool
    let loadThumbnails: @Sendable () async -> [CGImage]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var thumbnails: [CGImage] = []
    @State private var phase: Int = 1
    @State private var pair: Int = 0
    @State private var direction: Int = 0

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let size = min(112.0, width * 0.28)
            ZStack {
                Circle()
                    .fill(QColors.primary.opacity(0.04))
                    .frame(width: size * 2.6, height: size * 2.6)
                    .position(x: width / 2, y: height * 0.4)
                photo(index: pair, size: size)
                    .rotationEffect(.degrees(phase == 0 ? -24 : -9))
                    .scaleEffect(phase == 3 ? 0.35 : 1)
                    .opacity(phase == 0 || phase == 3 ? 0 : 1)
                    .position(position(second: false, width: width, height: height, size: size))
                photo(index: pair + 1, size: size)
                    .rotationEffect(.degrees(phase == 0 ? 22 : 8))
                    .scaleEffect(phase == 3 ? 0.35 : 1)
                    .opacity(phase == 0 || phase == 3 ? 0 : 1)
                    .position(position(second: true, width: width, height: height, size: size))
                Image(systemName: "tray.full.fill")
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(QColors.primary.opacity(0.7))
                    .scaleEffect(phase == 3 ? 1.08 : 1)
                    .position(x: width / 2, y: height * 0.8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
        .task(id: isRunning) {
            guard isRunning, thumbnails.isEmpty else { return }
            let loaded = await loadThumbnails()
            guard !Task.isCancelled else { return }
            thumbnails = loaded
        }
        .task(id: isRunning && !reduceMotion) {
            guard isRunning, !reduceMotion else {
                phase = 1
                return
            }
            do {
                while !Task.isCancelled {
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        phase = 0
                        direction = Int.random(in: 0..<4)
                        pair = thumbnails.isEmpty ? 0 : (pair + 2) % thumbnails.count
                    }
                    try await Task.sleep(for: .milliseconds(150))
                    withAnimation(.easeInOut(duration: 1.25)) { phase = 1 }
                    try await Task.sleep(for: .seconds(1.8))
                    withAnimation(.smooth(duration: 0.7)) { phase = 2 }
                    try await Task.sleep(for: .seconds(1))
                    withAnimation(.easeInOut(duration: 1)) { phase = 3 }
                    try await Task.sleep(for: .seconds(1.35))
                }
            } catch { }
        }
    }

    private func photo(index: Int, size: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(QColors.primary.opacity(0.12).gradient)
            if !thumbnails.isEmpty {
                Image(decorative: thumbnails[index % thumbnails.count], scale: 1)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size * 1.2)
                    .blur(radius: 5)
            } else {
                Image(systemName: "photo")
                    .font(.largeTitle)
                    .foregroundStyle(QColors.primary.opacity(0.4))
            }
        }
        .frame(width: size, height: size * 1.2)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(.white.opacity(0.75), lineWidth: 3)
        }
        .shadow(color: .black.opacity(0.12), radius: 10, y: 6)
    }

    private func position(second: Bool, width: CGFloat, height: CGFloat, size: CGFloat) -> CGPoint {
        if phase == 0 {
            let side = (direction + (second ? 2 : 0)) % 4
            switch side {
            case 0: return CGPoint(x: -size, y: height * 0.3)
            case 1: return CGPoint(x: width * 0.7, y: -size)
            case 2: return CGPoint(x: width + size, y: height * 0.5)
            default: return CGPoint(x: width * 0.3, y: height + size)
            }
        }
        if phase == 3 { return CGPoint(x: width / 2, y: height * 0.8) }
        let separation = phase == 2 ? size * 0.12 : size * 0.44
        return CGPoint(x: width / 2 + (second ? separation : -separation), y: height * 0.4)
    }
}
#endif
