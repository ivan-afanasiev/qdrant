import SwiftUI

enum ViewMode: String, CaseIterable {
    case cards
    case grid
}

struct ScanView: View {
    @Environment(\.dependencies) private var dependencies
    @Environment(\.scenePhase) private var scenePhase
    @State private var interactor = ScanInteractor()

    @State private var dragOffset: CGFloat = 0
    @State private var fullscreenPhoto: PhotoReference?

    var body: some View {
        content
            .navigationTitle(L10n.appTitle)
            .toolbar { toolbarContent }
            .task {
                if let deps = dependencies {
                    interactor.configure(deps: deps)
                    interactor.send(.launched)
                }
            }
            .onChange(of: scenePhase) { _, phase in
                interactor.send(.scenePhaseChanged(phase))
            }
            .onDisappear { interactor.teardown() }
            .fullScreenCover(item: $fullscreenPhoto) { photo in
                FullscreenPhotoView(photo: photo) {
                    fullscreenPhoto = nil
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 0) {
            if case .idle = interactor.coordinator.phase, !interactor.hasLaunched {
                loadingView
            } else if case .idle = interactor.coordinator.phase, interactor.hasLaunched {
                if interactor.hasGroups {
                    activeContent
                } else {
                    noGroupsView
                }
            } else {
                activeContent
            }
        }
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: QSpacing.md) {
            Spacer()
            ProgressView()
            Text(L10n.preparingToScan)
                .foregroundStyle(QColors.textTertiary)
            Spacer()
        }
    }

    // MARK: - No Groups

    private var noGroupsView: some View {
        VStack(spacing: QSpacing.md) {
            Spacer()
            QStatusIcon(QIcons.sparkles, size: QSize.iconLarge, color: QColors.success)
            Text(L10n.noDuplicatesFound)
                .font(QTypography.titleMedium)
            Text(L10n.libraryLooksClean)
                .foregroundStyle(QColors.textTertiary)
            Spacer()
        }
    }

    // MARK: - Active Content

    private var activeContent: some View {
        VStack(spacing: 0) {
            statusBanner

            switch interactor.viewMode {
            case .cards:
                cardsContent
            case .grid:
                gridContent
            }
        }
    }

    @ViewBuilder
    private var statusBanner: some View {
        if interactor.coordinator.isActive {
            scanProgressBar
                .padding(.horizontal)
                .padding(.top, QSpacing.sm)
        } else if interactor.coordinator.isInterrupted {
            interruptedBanner
                .padding(.horizontal)
                .padding(.top, QSpacing.sm)
        } else if interactor.showCompletedBadge {
            completedBadge
                .padding(.horizontal)
                .padding(.top, QSpacing.sm)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if interactor.coordinator.isActive {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    interactor.send(.cancelScan)
                } label: {
                    Text(L10n.cancel)
                        .font(QTypography.caption)
                }
                .buttonStyle(.borderless)
            }
        }

        if interactor.hasGroups {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    interactor.send(.switchViewMode(
                        interactor.viewMode == .cards ? .grid : .cards
                    ))
                } label: {
                    Image(systemName: interactor.viewMode == .cards
                        ? QIcons.squareGrid
                        : QIcons.rectangleStack)
                }
            }
        }
    }

    // MARK: - Cards Content

    private var cardsContent: some View {
        Group {
            switch interactor.reviewState.status {
            case .reviewing:
                reviewingSection
            case .loading:
                ReviewLoadingView()
            case .deletingGroup:
                ReviewDeletingView()
            case .allReviewed:
                ReviewAllDoneView(stats: interactor.reviewState.stats, onFinished: {})
            case .failed(let error):
                ReviewFailedView(error: error, onDismiss: {})
            case .noMoreGroups, .idle:
                if case .completed = interactor.coordinator.phase {
                    completedEmptyView
                } else {
                    scanningPlaceholder
                }
            }
        }
    }

    // MARK: - Grid Content

    private var gridContent: some View {
        InlineGroupGridView(
            state: interactor.gridState,
            useCases: interactor.groupGridUseCases,
            reviewUseCases: interactor.reviewUseCases,
            onGroupReviewed: { reviewedId in
                interactor.send(.groupReviewedFromGrid(reviewedId))
            }
        )
    }

    // MARK: - Progress Bar

    private var scanProgressBar: some View {
        VStack(spacing: QSpacing.xs) {
            ProgressView(value: interactor.coordinator.scanProgress)
                .tint(QColors.primary)

            HStack {
                if case .scanning(let processed, let total, let groupsFound) = interactor.coordinator.phase {
                    Text(L10n.scanProgressStatus(processed, total))
                        .font(QTypography.caption)
                        .foregroundStyle(QColors.textTertiary)
                    Spacer()
                    if groupsFound > 0 {
                        Text(L10n.groupsFoundSoFar(groupsFound))
                            .font(QTypography.caption)
                            .foregroundStyle(QColors.primary)
                    }
                }
            }
        }
    }

    private var interruptedBanner: some View {
        HStack(spacing: QSpacing.xs) {
            ProgressView()
                .controlSize(.small)
            Text(L10n.scanResuming)
                .font(QTypography.caption)
                .foregroundStyle(QColors.textSecondary)
            Spacer()
        }
        .padding(.vertical, QSpacing.xs)
    }

    private var scanningPlaceholder: some View {
        VStack(spacing: QSpacing.lg) {
            Spacer()
            progressRing(value: interactor.coordinator.scanProgress)

            Text(L10n.embeddingPhotos)
                .font(QTypography.bodyLarge)
            Text(L10n.scanningWithInlineDetection)
                .font(QTypography.bodyMedium)
                .foregroundStyle(QColors.textTertiary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding()
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

    // MARK: - Completed

    private var completedBadge: some View {
        HStack(spacing: QSpacing.xs) {
            Image(systemName: QIcons.successFill)
                .foregroundStyle(QColors.success)
            Text(L10n.scanComplete)
                .font(QTypography.caption)
                .foregroundStyle(QColors.textSecondary)
            Spacer()
        }
        .padding(.vertical, QSpacing.xs)
    }

    private var completedEmptyView: some View {
        VStack(spacing: QSpacing.md) {
            Spacer()
            QStatusIcon(QIcons.sparkles, size: QSize.iconLarge, color: QColors.success)
            Text(L10n.noDuplicatesFound)
                .font(QTypography.titleMedium)
            Text(L10n.libraryLooksClean)
                .foregroundStyle(QColors.textTertiary)
            Spacer()
        }
    }

    // MARK: - Review Section

    private var reviewingSection: some View {
        VStack(spacing: QSpacing.md) {
            headerBar
                .padding(.top, QSpacing.sm)

            if interactor.reviewProgressTotal > 0 {
                ProgressView(value: Double(interactor.reviewState.reviewedInSession), total: interactor.reviewProgressTotal)
                    .tint(QColors.primary)
                    .padding(.horizontal)
            }

            ReviewCardStack(
                group: interactor.reviewState.currentGroup,
                keptIds: interactor.reviewState.currentGroup.map { interactor.reviewState.keptIds(for: $0) } ?? [],
                dragOffset: $dragOffset,
                fullscreenPhoto: $fullscreenPhoto,
                onToggleKeep: { photo in
                    interactor.send(.toggleKeep(photo))
                },
                onSwipedOut: { interactor.send(.skipGroup) }
            )

            ReviewConfirmButton(
                group: interactor.reviewState.currentGroup,
                keptIds: interactor.reviewState.currentGroup.map { interactor.reviewState.keptIds(for: $0) } ?? [],
                onDelete: { interactor.send(.deleteGroup) },
                onSkip: { animateSkip() }
            )

            Text(L10n.tapToKeepHint)
                .font(QTypography.caption)
                .foregroundStyle(QColors.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
                .padding(.bottom, QSpacing.sm)
        }
    }

    private var headerBar: some View {
        HStack {
            Text(interactor.reviewGroupCounter)
                .font(QTypography.bodyLarge)
                .contentTransition(.numericText())
                .animation(.default, value: interactor.reviewGroupCounter)
            Spacer()
            Button(L10n.skip) {
                animateSkip()
            }
            .buttonStyle(.qGhost)
        }
        .padding(.horizontal)
    }

    // MARK: - Swipe Animation

    private func animateSkip() {
        guard interactor.reviewState.currentGroup != nil else { return }
        let screenWidth = UIScreen.main.bounds.width
        let exitX: CGFloat = -screenWidth * 1.5

        withAnimation(.easeIn(duration: 0.25)) {
            dragOffset = exitX
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            dragOffset = 0
            interactor.send(.skipGroup)
        }
    }
}
