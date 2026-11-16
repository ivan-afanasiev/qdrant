#if os(iOS)
import SwiftUI
import SweepDesignSystem
import SweepDomain
import SweepFeatureState
import SweepUseCases

public struct SettingsView: View {
    private let store: Store<SettingsFeature>

    public init(store: Store<SettingsFeature>) {
        self.store = store
    }

    public var body: some View {
        Form {
            if let preferences = store.state.preferences {
                Section {
                    Picker(selection: Binding(
                        get: { preferences.datePreset },
                        set: { store.send(.datePresetSelected($0)) }
                    )) {
                        ForEach(DateScopePreset.allCases, id: \.self) { Text($0.title).tag($0) }
                    } label: {
                        Text(L10n.settingsScanPeriodHeader)
                    }
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
                    .pickerStyle(.segmented)
                } header: {
                    Text(L10n.detection)
                } footer: {
                    Text(L10n.similarityFooter)
                }
            }

            Section {
                Button(L10n.rescanLibrary) { store.send(.rescanTapped) }
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
        case .lastWeek: L10n.lastWeek
        case .lastMonth: L10n.lastMonth
        case .last3Months: L10n.last3Months
        case .last6Months: L10n.last6Months
        case .lastYear: L10n.lastYear
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
#endif
