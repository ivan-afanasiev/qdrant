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
struct ReviewControls: View {
    let card: ReviewFeature.Card
    let isBusy: Bool
    let send: (ReviewFeature.Action) -> Void

    var body: some View {
        let deleteCount = card.snapshot.members.count - card.keep.count
        GlassEffectContainer(spacing: QSpacing.sm) {
            HStack(spacing: QSpacing.sm) {
                Button(L10n.skip) { send(.skipTapped) }
                    .buttonStyle(.glass)

                if card.keep.isEmpty {
                    Button(L10n.keepAll) { send(.keepAllTapped) }
                        .buttonStyle(.glass)
                    Button(role: .destructive) {
                        send(.deleteAllTapped)
                    } label: {
                        Text(L10n.deleteAll).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(QColors.destructive)
                } else if deleteCount == 0 {
                    Button {
                        send(.commitTapped)
                    } label: {
                        Text(L10n.keepAll).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(QColors.success)
                } else {
                    Button(role: .destructive) {
                        send(.commitTapped)
                    } label: {
                        Text(L10n.deleteNPhotos(deleteCount)).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(QColors.destructive)
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
}
#endif
