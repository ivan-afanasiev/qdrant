import SwiftUI

struct OnboardingWelcomeStep: View {
    var body: some View {
        VStack(spacing: QSpacing.xxl) {
            Spacer()

            Image(systemName: QIcons.sparkles)
                .font(.system(size: 72))
                .foregroundStyle(QColors.primary)

            VStack(spacing: QSpacing.sm) {
                Text(L10n.appTitle)
                    .font(QTypography.displayMedium)

                Text(L10n.onboardingWelcomeSubtitle)
                    .font(QTypography.bodyMedium)
                    .foregroundStyle(QColors.textSecondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: QSpacing.lg) {
                featureRow(
                    icon: "magnifyingglass.circle.fill",
                    title: L10n.onboardingFeatureScanTitle,
                    subtitle: L10n.onboardingFeatureScanSubtitle
                )
                featureRow(
                    icon: "cube.fill",
                    title: L10n.onboardingFeatureVectorTitle,
                    subtitle: L10n.onboardingFeatureVectorSubtitle
                )
                featureRow(
                    icon: "hand.draw.fill",
                    title: L10n.onboardingFeatureSwipeTitle,
                    subtitle: L10n.onboardingFeatureSwipeSubtitle
                )
            }
            .padding(.horizontal, QSpacing.lg)

            Spacer()
            Spacer()
        }
        .padding()
    }

    private func featureRow(icon: String, title: LocalizedStringKey, subtitle: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: QSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundStyle(QColors.primary)
                .frame(width: 44)

            VStack(alignment: .leading, spacing: QSpacing.xxxs) {
                Text(title)
                    .font(QTypography.bodyLarge)
                Text(subtitle)
                    .font(QTypography.bodySmall)
                    .foregroundStyle(QColors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
