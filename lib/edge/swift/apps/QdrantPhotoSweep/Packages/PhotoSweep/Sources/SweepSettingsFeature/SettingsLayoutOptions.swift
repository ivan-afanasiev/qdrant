#if os(iOS) && DEBUG
import SwiftUI
import SweepDesignSystem
import SweepDomain

// Design options for the Settings controls that break with long localized labels: the
// date-range picker and the Strict/Balanced/Loose segmented control. Preview-only: the
// chosen option replaces the matching sections in `SettingsView`, and this file is removed.

/// Option A — navigation rows: the date range opens its own list (label left, value right,
/// chevron), and similarity becomes an inline checkmark list. Nothing shares a line except
/// a label and its value.
private struct SettingsOptionA: View {
    @State private var preset = DateScopePreset.lastYear
    @State private var similarity = SimilarityPreset.balanced

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(selection: $preset) {
                        ForEach(DateScopePreset.allCases, id: \.self) { Text($0.title).tag($0) }
                    } label: {
                        Text(L10n.settingsScanPeriodHeader)
                    }
                    .pickerStyle(.navigationLink)
                } footer: {
                    Text(L10n.settingsScanPeriodFooter)
                }
                Section {
                    Picker(selection: $similarity) {
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
                RescanSection()
            }
            .navigationTitle(Text(L10n.settings))
        }
    }
}

/// Option B — everything visible: both choices are inline checkmark lists, so every option
/// gets a full row and long labels wrap naturally. Longest screen, zero hidden state.
private struct SettingsOptionB: View {
    @State private var preset = DateScopePreset.lastYear
    @State private var similarity = SimilarityPreset.balanced

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(selection: $preset) {
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
                    Picker(selection: $similarity) {
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
                RescanSection()
            }
            .navigationTitle(Text(L10n.settings))
        }
    }
}

/// Option C — compact menus: label and current value on one row with a menu, falling back to
/// a stacked label above the value when both do not fit (Russian, narrow folded Duo).
private struct SettingsOptionC: View {
    @State private var preset = DateScopePreset.lastYear
    @State private var similarity = SimilarityPreset.balanced

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    AdaptiveMenuRow(title: L10n.settingsScanPeriodHeader) {
                        Picker(selection: $preset) {
                            ForEach(DateScopePreset.allCases, id: \.self) { Text($0.title).tag($0) }
                        } label: {
                            Text(L10n.settingsScanPeriodHeader)
                        }
                    }
                } footer: {
                    Text(L10n.settingsScanPeriodFooter)
                }
                Section {
                    AdaptiveMenuRow(title: L10n.similarityThreshold) {
                        Picker(selection: $similarity) {
                            ForEach(SimilarityPreset.allCases, id: \.self) { Text($0.title).tag($0) }
                        } label: {
                            Text(L10n.similarityThreshold)
                        }
                    }
                } header: {
                    Text(L10n.detection)
                } footer: {
                    Text(L10n.similarityFooter)
                }
                RescanSection()
            }
            .navigationTitle(Text(L10n.settings))
        }
    }
}

/// A label and a menu picker side by side, or stacked when they do not fit on one line.
private struct AdaptiveMenuRow<PickerContent: View>: View {
    let title: LocalizedStringResource
    @ViewBuilder let picker: () -> PickerContent

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                Text(title).fixedSize()
                Spacer(minLength: QSpacing.sm)
                picker().labelsHidden().pickerStyle(.menu).fixedSize()
            }
            VStack(alignment: .leading, spacing: QSpacing.xxs) {
                Text(title)
                picker().labelsHidden().pickerStyle(.menu)
            }
        }
    }
}

/// Same in every option: the rescan row with an icon so the long label reads as an action.
private struct RescanSection: View {
    var body: some View {
        Section {
            Button {} label: {
                Label { Text(L10n.rescanLibrary) } icon: { Image(systemName: QIcons.refresh) }
            }
        } header: {
            Text(L10n.libraryHeader)
        } footer: {
            Text(L10n.rescanFooter)
        }
    }
}

#Preview("A · navigation rows · Russian", traits: .fixedLayout(width: 393, height: 852)) {
    SettingsOptionA().environment(\.locale, Locale(identifier: "ru")).tint(QColors.primary)
}

#Preview("B · inline lists · Russian", traits: .fixedLayout(width: 393, height: 852)) {
    SettingsOptionB().environment(\.locale, Locale(identifier: "ru")).tint(QColors.primary)
}

#Preview("C · adaptive menus · Russian", traits: .fixedLayout(width: 393, height: 852)) {
    SettingsOptionC().environment(\.locale, Locale(identifier: "ru")).tint(QColors.primary)
}

#Preview("C · adaptive menus · German · narrow (folded Duo)", traits: .fixedLayout(width: 320, height: 852)) {
    SettingsOptionC().environment(\.locale, Locale(identifier: "de")).tint(QColors.primary)
}

#Preview("A · navigation rows · German · wide (unfolded Duo)", traits: .fixedLayout(width: 700, height: 852)) {
    SettingsOptionA().environment(\.locale, Locale(identifier: "de")).tint(QColors.primary)
}
#endif
