#if os(iOS)
import SwiftUI
import SweepDesignSystem
import SweepDomain

/// What a swipe in one direction does: shown as a badge while dragging.
struct SwipeAction {
    let title: Text
    let icon: String
    let tint: Color
    /// Skip and Keep All send the card away; deletions spring back so the Photos
    /// confirmation appears over the card, which stays if the person declines.
    let fliesOff: Bool
    let perform: () -> Void
}

/// A deck of review cards: the group sits on a card with two more peeking behind it.
/// Dragging moves and tilts the card, fades in a badge for the action that releasing will
/// trigger (left: Skip; right: the card's commit action), tints the card edge and ticks a
/// haptic at the threshold. A fling uses the release velocity; short drags spring back.
struct ReviewCardStack<Content: View>: View {
    let snapshot: ReviewGroupSnapshot
    let isBusy: Bool
    let leading: SwipeAction
    let trailing: SwipeAction
    @ViewBuilder let content: () -> Content

    @State private var drag: CGSize = .zero
    @State private var hasFlownOff = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        snapshot: ReviewGroupSnapshot,
        isBusy: Bool,
        leading: SwipeAction,
        trailing: SwipeAction,
        initialDrag: CGSize = .zero,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.snapshot = snapshot
        self.isBusy = isBusy
        self.leading = leading
        self.trailing = trailing
        self.content = content
        _drag = State(initialValue: initialDrag)
    }

    private static var cardShape: RoundedRectangle { RoundedRectangle(cornerRadius: QRadius.xl, style: .continuous) }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let threshold = width * 0.28
            let progress = min(abs(drag.width) / threshold, 1)
            let action = drag.width < 0 ? leading : trailing
            ZStack {
                deckCard(depth: 2, progress: progress)
                deckCard(depth: 1, progress: progress)
                card(action: action, progress: progress)
                    .id(snapshot.id)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.94).combined(with: .opacity),
                        removal: .identity
                    ))
                    .offset(drag)
                    .rotationEffect(.degrees(reduceMotion ? 0 : Double(drag.width / width) * 12), anchor: .bottom)
                    .simultaneousGesture(swipeGesture(width: width, threshold: threshold))
                    .accessibilityAction(named: Text(L10n.skip)) { leading.perform() }
                    .accessibilityAction(named: trailing.title) { trailing.perform() }
            }
            .padding(.horizontal, QSpacing.sm)
            .padding(.top, QSpacing.xs)
            .padding(.bottom, QSpacing.lg)
            .sensoryFeedback(.selection, trigger: progress >= 1)
        }
        .animation(QAnimation.springDefault, value: snapshot.id)
        .onChange(of: snapshot.id) {
            // The next card took the place of the one that flew off.
            var reset = Transaction()
            reset.disablesAnimations = true
            withTransaction(reset) { drag = .zero }
            hasFlownOff = false
        }
        .onChange(of: isBusy) { _, busy in
            // The action failed or was declined and the same card stays: bring it back.
            guard !busy, hasFlownOff else { return }
            hasFlownOff = false
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) { drag = .zero }
        }
    }

    private func card(action: SwipeAction, progress: CGFloat) -> some View {
        content()
            .scrollIndicators(.hidden)
            .background(QColors.surface, in: Self.cardShape)
            .clipShape(Self.cardShape)
            .overlay {
                Self.cardShape
                    .strokeBorder(action.tint.opacity(progress), lineWidth: 3)
            }
            // The badge sits on the side that stays on screen, like a stamp.
            .overlay(alignment: drag.width < 0 ? .topTrailing : .topLeading) {
                badge(action, progress: progress)
                    .rotationEffect(.degrees(reduceMotion ? 0 : (drag.width < 0 ? 8 : -8)))
                    .padding(.top, QSpacing.xl)
            }
            .shadow(color: .black.opacity(0.14), radius: 14, y: 6)
    }

    private func badge(_ action: SwipeAction, progress: CGFloat) -> some View {
        Label { action.title } icon: { Image(systemName: action.icon) }
            .font(QTypography.titleMedium.weight(.semibold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, QSpacing.lg)
            .padding(.vertical, QSpacing.sm)
            .background(action.tint, in: Capsule())
            .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
            .scaleEffect(0.7 + 0.3 * progress)
            .opacity(Double(progress))
            .padding(.horizontal, QSpacing.md)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// A card behind the current one; the nearer one grows into place while dragging.
    private func deckCard(depth: CGFloat, progress: CGFloat) -> some View {
        let lift = depth == 1 ? progress : 0
        return Self.cardShape
            .fill(QColors.surface)
            .overlay { Self.cardShape.strokeBorder(QColors.border, lineWidth: 1) }
            .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
            .scaleEffect(1 - 0.05 * (depth - lift))
            .offset(y: 14 * (depth - lift))
            .opacity(1 - 0.25 * Double(depth))
            .accessibilityHidden(true)
    }

    private func swipeGesture(width: CGFloat, threshold: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 16)
            .onChanged { value in
                guard !isBusy, !hasFlownOff else { return }
                // Vertical drags scroll the photos; a mostly horizontal one moves the card.
                guard drag != .zero || abs(value.translation.width) > abs(value.translation.height) else { return }
                drag = CGSize(width: value.translation.width, height: reduceMotion ? 0 : value.translation.height * 0.15)
            }
            .onEnded { value in
                guard drag != .zero, !isBusy else { return }
                let predicted = value.predictedEndTranslation.width
                let committed = abs(drag.width) > threshold
                    || (abs(predicted) > width * 0.6 && predicted.sign == drag.width.sign)
                guard committed else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { drag = .zero }
                    return
                }
                let action = drag.width < 0 ? leading : trailing
                if action.fliesOff {
                    hasFlownOff = true
                    let direction: CGFloat = drag.width < 0 ? -1 : 1
                    let flight = CGSize(width: direction * width * 1.5, height: drag.height + value.velocity.height * 0.1)
                    withAnimation(.easeOut(duration: 0.25)) { drag = flight }
                    action.perform()
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { drag = .zero }
                    action.perform()
                }
            }
    }
}

/// All photos of one group; tap to keep, expand for preview.
struct GroupComparisonView: View {
    let snapshot: ReviewGroupSnapshot
    let keep: Set<AssetID>
    let details: [AssetID: PhotoAsset]
    let images: ReviewImages
    let onToggleKeep: (AssetID) -> Void
    let onPreview: (AssetID) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: QSpacing.sm) {
                Text(L10n.tapToKeepHint)
                    .font(QTypography.bodySmall)
                    .foregroundStyle(QColors.textSecondary)
                    .multilineTextAlignment(.center)
                Text(L10n.similarPhotos(snapshot.members.count))
                    .font(QTypography.bodyMedium)
                    .foregroundStyle(QColors.textTertiary)
                LazyVGrid(columns: columns, spacing: QSpacing.sm) {
                    ForEach(snapshot.members, id: \.self) { asset in
                        PhotoCardView(
                            asset: asset,
                            photo: details[asset],
                            isKept: keep.contains(asset),
                            images: images,
                            onTap: { onToggleKeep(asset) },
                            onPreview: { onPreview(asset) }
                        )
                    }
                }
            }
            .padding()
        }
    }

    private var columns: [GridItem] {
        snapshot.members.count <= 2
            ? [GridItem(.flexible())]
            : [GridItem(.flexible()), GridItem(.flexible())]
    }
}





#if DEBUG
/// Mid-swipe states for checking the badge, tint and deck without a device.
private struct SwipePreview: View {
    let drag: CGFloat

    var body: some View {
        let snapshot = ReviewGroupSnapshot(
            id: GroupID(UUID()), revision: MembershipRevision(1), discoveryRevision: DiscoveryRevision(1),
            members: [AssetID("a"), AssetID("b")]
        )
        ReviewCardStack(
            snapshot: snapshot,
            isBusy: false,
            leading: SwipeAction(title: Text(L10n.skip), icon: QIcons.skip, tint: QColors.accent, fliesOff: true, perform: {}),
            trailing: SwipeAction(title: Text(L10n.deleteAll), icon: QIcons.trashFill, tint: QColors.destructive, fliesOff: false, perform: {}),
            initialDrag: CGSize(width: drag, height: 6)
        ) {
            VStack(spacing: QSpacing.sm) {
                Text(L10n.tapToKeepHint).font(QTypography.bodySmall).foregroundStyle(QColors.textSecondary)
                ForEach(0..<2, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: QRadius.lg).fill(QColors.surfaceMuted).aspectRatio(4 / 3, contentMode: .fit)
                }
                Spacer(minLength: 0)
            }
            .padding()
        }
    }
}

#Preview("Swipe · left (Skip)", traits: .fixedLayout(width: 393, height: 700)) {
    SwipePreview(drag: -130).background(QColors.surfaceBackground)
}

#Preview("Swipe · right (Delete All)", traits: .fixedLayout(width: 393, height: 700)) {
    SwipePreview(drag: 90).background(QColors.surfaceBackground)
}
#endif
#endif
