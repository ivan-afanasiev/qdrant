#if os(iOS)
import SwiftUI
import SweepDesignSystem
import SweepDomain
import SweepFeatureState
import SweepUseCases

public struct SettingsView: View {
    private let store: Store<SettingsFeature>
    @Environment(\.dismiss) private var dismiss

    public init(store: Store<SettingsFeature>) {
        self.store = store
    }

    public var body: some View {
        Form {
            if let preferences = store.state.preferences {
                // Inline checkmark lists (design option B, chosen 2026-11-18): every choice
                // gets its own row, so long localized labels wrap instead of truncating.
                Section {
                    Picker(selection: Binding(
                        get: { preferences.datePreset },
                        set: { store.send(.datePresetSelected($0)) }
                    )) {
                        ForEach(DateScopePreset.allCases, id: \.self) { Text($0.title).tag($0) }
                    } label: {
                        Text(L10n.settingsScanPeriodHeader)
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text(L10n.settingsScanPeriodHeader)
                } footer: {
                    Text(L10n.settingsScanPeriodFooter)
                }

                Section {
                    Picker(selection: Binding(
                        get: { preferences.similarity },
                        set: { store.send(.similaritySelected($0)) }
                    )) {
                        ForEach(SimilarityPreset.allCases, id: \.self) { Text($0.title).tag($0) }
                    } label: {
                        Text(L10n.similarityThreshold)
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text(L10n.detection)
                } footer: {
                    Text(L10n.similarityFooter)
                }
            }

            Section {
                Button { store.send(.rescanTapped) } label: {
                    Label { Text(L10n.rescanLibrary) } icon: { Image(systemName: QIcons.refresh) }
                }
            } header: {
                Text(L10n.libraryHeader)
            } footer: {
                Text(L10n.rescanFooter)
            }

            if let statistics = store.state.statistics {
                StatisticsSection(statistics: statistics)
            }

            Section {
                Button(L10n.resetLocalData, role: .destructive) { store.send(.resetTapped) }
            }

            Section(header: Text(L10n.about)) {
                LabeledContent { Text(L10n.qdrantEdge) } label: { Text(L10n.engine) }
                LabeledContent { Text(L10n.appleVision) } label: { Text(L10n.embeddings) }
            }
        }
        .navigationTitle(Text(L10n.settings))
        .disabled(store.state.isWorking)
        .overlay {
            if store.state.isWorking {
                ProgressView()
                    .qGlassPanel()
            }
        }
        .confirmationDialog(
            Text(L10n.resetConfirmTitle),
            isPresented: Binding(
                get: { store.state.isConfirmingReset },
                set: { if !$0 { store.send(.resetCancelled) } }
            ),
            titleVisibility: .visible
        ) {
            Button(L10n.resetConfirm, role: .destructive) { store.send(.resetConfirmed) }
        } message: {
            Text(L10n.resetConfirmMessage)
        }
        .alert(Text(L10n.settingsFailed), isPresented: Binding(
            get: { store.state.didFail },
            set: { if !$0 { store.send(.failureDismissed) } }
        )) {
            Button(L10n.noticeOK) { store.send(.failureDismissed) }
        }
        .task { store.send(.onAppear) }
        .onChange(of: store.state.isDismissRequested) { _, requested in
            if requested { dismiss() }
        }
    }
}

/// Statistics from confirmed outcomes. Storage freed is an estimate and excludes unknown sizes.
private struct StatisticsSection: View {
    let statistics: LibraryStatistics

    var body: some View {
        Section {
            row(L10n.statAnalyzed, statistics.vectorizedPhotos.formatted())
            row(L10n.statUnavailable, statistics.unavailablePhotos.formatted())
            row(L10n.statReviewed, statistics.reviewedGroups.formatted())
            row(L10n.settingsStatPhotosDeleted, statistics.deletedPhotos.formatted())
            row(L10n.statFreed, ByteCountFormatter.string(fromByteCount: statistics.estimatedBytesFreed, countStyle: .file))
        } header: {
            Text(L10n.settingsStatHeader)
        } footer: {
            VStack(alignment: .leading, spacing: QSpacing.xxs) {
                if statistics.deletionsWithUnknownSize > 0 {
                    Text(L10n.statUnknownSizes(statistics.deletionsWithUnknownSize))
                }
                Text(L10n.statEstimateNote)
            }
        }
    }

    private func row(_ label: LocalizedStringResource, _ value: String) -> some View {
        LabeledContent {
            Text(value).monospacedDigit()
        } label: {
            Text(label)
        }
    }
}

extension DateScopePreset {
    var title: LocalizedStringResource {
        switch self {
        case .last3Months: L10n.last3Months
        case .lastYear: L10n.lastYear
        case .last3Years: L10n.last3Years
        case .last5Years: L10n.last5Years
        case .allTime: L10n.allTime
        }
    }
}

extension SimilarityPreset {
    var title: LocalizedStringResource {
        switch self {
        case .strict: L10n.similarityStrict
        case .balanced: L10n.similarityBalanced
        case .loose: L10n.similarityLoose
        }
    }
}

#if DEBUG
@MainActor
private func previewSettingsStore() -> Store<SettingsFeature> {
    let client = SettingsClient(
        loadPreferences: { Preferences(datePreset: .last3Years, similarity: .balanced, isOnboardingCompleted: true) },
        loadStatistics: {
            LibraryStatistics(vectorizedPhotos: 18_215, unavailablePhotos: 3, reviewedGroups: 55, deletedPhotos: 6, estimatedBytesFreed: 42_000_000, deletionsWithUnknownSize: 1)
        },
        updateDateScope: { _ in true },
        updateSimilarity: { _ in true },
        rescan: { true },
        reset: { true }
    )
    return Store(initialState: SettingsFeature.State(), reducer: SettingsFeature(client: client))
}

#Preview("Settings · Russian") {
    NavigationStack { SettingsView(store: previewSettingsStore()) }
        .tint(QColors.primary)
        .environment(\.locale, Locale(identifier: "ru"))
}

#Preview("Settings · German · narrow (folded Duo)", traits: .fixedLayout(width: 320, height: 900)) {
    NavigationStack { SettingsView(store: previewSettingsStore()) }
        .tint(QColors.primary)
        .environment(\.locale, Locale(identifier: "de"))
}
#endif
#endif
