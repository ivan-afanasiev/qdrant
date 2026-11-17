#if os(iOS)
import SwiftUI
import SweepDesignSystem
import SweepDomain
import SweepFeatureState

public struct OnboardingView: View {
    private let store: Store<OnboardingFeature>
    @Environment(\.openURL) private var openURL

    public init(store: Store<OnboardingFeature>) {
        self.store = store
    }

    public var body: some View {
        VStack(spacing: QSpacing.xl) {
            Spacer(minLength: QSpacing.lg)
            content
                .frame(maxWidth: .infinity)
                .transition(.opacity)
            Spacer(minLength: QSpacing.lg)
            controls
        }
        .padding(QSpacing.lg)
        .animation(.default, value: store.state.step)
    }

    @ViewBuilder
    private var content: some View {
        switch store.state.step {
        case .welcome:
            header(icon: QIcons.sparkles, title: L10n.appTitle, subtitle: L10n.onboardingWelcomeSubtitle)
        case .photoAccess:
            VStack(spacing: QSpacing.md) {
                header(icon: QIcons.photoStack, title: L10n.onboardingPermissionTitle, subtitle: L10n.onboardingPermissionSubtitle)
                if store.state.isAccessDenied {
                    Text(L10n.onboardingPermissionDenied)
                        .font(QTypography.bodySmall)
                        .foregroundStyle(QColors.error)
                        .multilineTextAlignment(.center)
                }
            }
        case .notifications:
            header(icon: QIcons.clock, title: L10n.onboardingNotificationsTitle, subtitle: L10n.onboardingNotificationsSubtitle)
        case .dateRange:
            VStack(spacing: QSpacing.lg) {
                header(icon: QIcons.squareGrid, title: L10n.onboardingScanPeriodTitle, subtitle: L10n.onboardingScanPeriodSubtitle)
                DatePresetPicker(selection: store.state.datePreset) { store.send(.datePresetSelected($0)) }
                if store.state.didFailToComplete {
                    Text(L10n.onboardingStartFailed)
                        .font(QTypography.bodySmall)
                        .foregroundStyle(QColors.error)
                }
            }
        }
    }

    @ViewBuilder
    private var controls: some View {
        GlassEffectContainer(spacing: QSpacing.md) {
            VStack(spacing: QSpacing.sm) {
                switch store.state.step {
                case .welcome:
                    primaryButton(L10n.onboardingNext) { store.send(.continueTapped) }
                case .photoAccess:
                    if store.state.isAccessDenied {
                        primaryButton(L10n.openSettings) {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                openURL(url)
                            }
                        }
                    } else {
                        primaryButton(L10n.onboardingGrantAccess) { store.send(.allowPhotosTapped) }
                    }
                case .notifications:
                    primaryButton(L10n.onboardingNotificationsAllow) { store.send(.allowNotificationsTapped) }
                    secondaryButton(L10n.onboardingNotificationsSkip) { store.send(.skipNotificationsTapped) }
                case .dateRange:
                    primaryButton(L10n.onboardingGetStarted) { store.send(.startTapped) }
                }
            }
        }
        .disabled(store.state.isWorking)
    }

    private func header(icon: String, title: LocalizedStringResource, subtitle: LocalizedStringResource) -> some View {
        VStack(spacing: QSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: QSize.iconXLarge))
                .foregroundStyle(QColors.primary)
                .accessibilityHidden(true)
            Text(title)
                .font(QTypography.titleLarge)
                .multilineTextAlignment(.center)
            Text(subtitle)
                .font(QTypography.bodyMedium)
                .foregroundStyle(QColors.textSecondary)
                .multilineTextAlignment(.center)
        }
    }

    private func primaryButton(_ title: LocalizedStringResource, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            buttonLabel(title)
        }
        .buttonStyle(.glassProminent)
        .tint(QColors.primary)
        .controlSize(.large)
    }

    /// Same size as the primary button, with the regular glass style.
    private func secondaryButton(_ title: LocalizedStringResource, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            buttonLabel(title)
        }
        .buttonStyle(.glass)
        .controlSize(.large)
    }

    private func buttonLabel(_ title: LocalizedStringResource) -> some View {
        Text(title)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity)
    }
}

/// Date range presets; shared by onboarding and Settings.
public struct DatePresetPicker: View {
    private let selection: DateScopePreset
    private let onSelect: @MainActor (DateScopePreset) -> Void

    public init(selection: DateScopePreset, onSelect: @escaping @MainActor (DateScopePreset) -> Void) {
        self.selection = selection
        self.onSelect = onSelect
    }

    public var body: some View {
        Picker(selection: Binding(get: { selection }, set: onSelect)) {
            ForEach(DateScopePreset.allCases, id: \.self) { preset in
                Text(preset.title).tag(preset)
            }
        } label: {
            Text(L10n.onboardingScanPeriodTitle)
        }
        .pickerStyle(.inline)
        .labelsHidden()
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
#endif
