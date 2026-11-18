#if os(iOS)
import SwiftUI
import SweepDesignSystem
import SweepDomain
import SweepFeatureState

/// Tinder-like card review: one group at a time, keep selection, Skip (swipe), explicit
/// delete-all, and fullscreen preview. No grid.
public struct ReviewView: View {
    private let store: Store<ReviewFeature>
    private let images: ReviewImages
    private let isLibraryWorking: Bool
    @State private var dragOffset: CGFloat = 0
    @State private var preview: PreviewTarget?
    @State private var details: [AssetID: PhotoAsset] = [:]

    /// - Parameter isLibraryWorking: vectorization is still producing vectors, so an
    ///   exhausted discovery is not "All done" yet; more groups can still appear.
    public init(store: Store<ReviewFeature>, images: ReviewImages, isLibraryWorking: Bool = false) {
        self.store = store
        self.images = images
        self.isLibraryWorking = isLibraryWorking
    }

    public var body: some View {
        Group {
            if let card = store.state.card {
                cardContent(card)
            } else {
                emptyState
            }
        }
        .task { store.send(.onAppear) }
        .onDisappear { store.send(.onDisappear) }
        .task(id: store.state.card?.snapshot) {
            guard let snapshot = store.state.card?.snapshot else { return }
            details = await images.details(snapshot.members)
        }
        .fullScreenCover(item: $preview) { target in
            FullscreenPhotoView(asset: target.id, images: images) { preview = nil }
        }
        .alert(noticeTitle, isPresented: noticeBinding) {
            Button(L10n.noticeOK) { store.send(.noticeDismissed) }
        }
    }

    /// The photos fill the screen and scroll under the navigation bar and the controls,
    /// which sit in a bottom bar with the system scroll edge effect.
    private func cardContent(_ card: ReviewFeature.Card) -> some View {
        ReviewCardStack(snapshot: card.snapshot, dragOffset: $dragOffset, onSwipedOut: { store.send(.skipTapped) }) {
            GroupComparisonView(
                snapshot: card.snapshot,
                keep: card.keep,
                details: details,
                images: images,
                onToggleKeep: { store.send(.keepToggled($0)) },
                onPreview: { preview = PreviewTarget(id: $0) }
            )
        }
        .disabled(store.state.pending != nil)
        .safeAreaBar(edge: .bottom) {
            ReviewControls(card: card, isBusy: store.state.pending != nil) { action in
                store.send(action)
            }
            .padding(.horizontal)
            .padding(.bottom, QSpacing.sm)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: QSpacing.lg) {
            Spacer()
            switch store.state.discovery?.status {
            case .exhausted where !isLibraryWorking:
                QStatusIcon(QIcons.successFill, size: QSize.iconXLarge, color: QColors.success)
                Text(L10n.allDone)
                    .font(QTypography.titleMedium)
                Text(L10n.libraryLooksClean)
                    .font(QTypography.bodyMedium)
                    .foregroundStyle(QColors.textSecondary)
            case .failed:
                QStatusIcon(QIcons.warningFill, size: QSize.iconLarge, color: QColors.error)
                Text(L10n.error)
                    .font(QTypography.titleMedium)
            default:
                ProgressView()
                Text(L10n.findingDuplicates)
                    .font(QTypography.bodyLarge)
                Text(L10n.findingDuplicatesSubtitle)
                    .font(QTypography.bodyMedium)
                    .foregroundStyle(QColors.textSecondary)
            }
            Spacer()
        }
        .multilineTextAlignment(.center)
        .padding()
    }

    private var noticeBinding: Binding<Bool> {
        Binding(
            get: { store.state.notice != nil },
            set: { if !$0 { store.send(.noticeDismissed) } }
        )
    }

    private var noticeTitle: Text {
        switch store.state.notice {
        case .emptySelection: Text(L10n.noticeEmptySelection)
        case .conflictRefreshed: Text(L10n.noticeConflict)
        case .deletionDeclined: Text(L10n.noticeDeclined)
        case .commitFailed: Text(L10n.noticeCommitFailed)
        case .skipFailed: Text(L10n.noticeSkipFailed)
        case nil: Text(verbatim: "")
        }
    }
}

struct PreviewTarget: Identifiable {
    let id: AssetID
}

/// Commit actions for the current selection. An empty selection never deletes by itself.
/// Review actions (design option C, chosen 2026-11-18): Skip and Keep All are round icon
/// buttons, so the row's width goes to the one labeled action. Long localized labels
/// (German, Russian) and narrow widths fit without wrapping.
struct ReviewControls: View {
    let card: ReviewFeature.Card
    let isBusy: Bool
    let send: (ReviewFeature.Action) -> Void

    var body: some View {
        let deleteCount = card.snapshot.members.count - card.keep.count
        GlassEffectContainer(spacing: QSpacing.sm) {
            HStack(spacing: QSpacing.sm) {
                iconButton(QIcons.skip, label: L10n.skip) { send(.skipTapped) }

                if card.keep.isEmpty {
                    iconButton(QIcons.checkmark, label: L10n.keepAll) { send(.keepAllTapped) }
                    primaryButton(Text(L10n.deleteAll), icon: QIcons.trashFill, tint: QColors.destructive, role: .destructive) {
                        send(.deleteAllTapped)
                    }
                } else if deleteCount == 0 {
                    primaryButton(Text(L10n.keepAll), icon: QIcons.successFill, tint: QColors.success, role: nil) {
                        send(.commitTapped)
                    }
                } else {
                    primaryButton(Text(L10n.deleteNPhotos(deleteCount)), icon: QIcons.trashFill, tint: QColors.destructive, role: .destructive) {
                        send(.commitTapped)
                    }
                }
            }
        }
        .controlSize(.large)
        .disabled(isBusy)
        .overlay {
            if isBusy {
                ProgressView()
            }
        }
    }

    private func iconButton(_ symbol: String, label: LocalizedStringResource, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title3.weight(.semibold))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .accessibilityLabel(Text(label))
    }

    private func primaryButton(_ title: Text, icon: String, tint: Color, role: ButtonRole?, action: @escaping () -> Void) -> some View {
        Button(role: role, action: action) {
            Label { title } icon: { Image(systemName: icon) }
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glassProminent)
        .tint(tint)
    }
}

#if DEBUG
private func previewCard(keep: Set<AssetID>) -> ReviewFeature.Card {
    let members = [AssetID("a"), AssetID("b"), AssetID("c")]
    let snapshot = ReviewGroupSnapshot(
        id: GroupID(UUID()), revision: MembershipRevision(1), discoveryRevision: DiscoveryRevision(1), members: members
    )
    return ReviewFeature.Card(snapshot: snapshot, keep: keep)
}

/// The three control states: nothing selected, one photo kept, all photos kept.
private struct ReviewControlsPreview: View {
    let locale: String

    var body: some View {
        VStack(spacing: QSpacing.lg) {
            ReviewControls(card: previewCard(keep: []), isBusy: false) { _ in }
            ReviewControls(card: previewCard(keep: [AssetID("a")]), isBusy: false) { _ in }
            ReviewControls(card: previewCard(keep: [AssetID("a"), AssetID("b"), AssetID("c")]), isBusy: false) { _ in }
        }
        .padding()
        .tint(QColors.primary)
        .environment(\.locale, Locale(identifier: locale))
    }
}

#Preview("Review controls · German", traits: .fixedLayout(width: 393, height: 320)) {
    ReviewControlsPreview(locale: "de")
}

#Preview("Review controls · Russian · narrow (folded Duo)", traits: .fixedLayout(width: 320, height: 320)) {
    ReviewControlsPreview(locale: "ru")
}
#endif
#endif
