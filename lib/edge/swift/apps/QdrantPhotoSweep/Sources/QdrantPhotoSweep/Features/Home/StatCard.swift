import SwiftUI

struct StatCard: View {
    let icon: String
    let value: String
    let label: LocalizedStringKey

    var body: some View {
        VStack(spacing: QSpacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(QColors.primary)

            Text(value)
                .font(QTypography.numericLarge)

            Text(label)
                .font(QTypography.caption)
                .foregroundStyle(QColors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, QSpacing.lg)
        .background(QColors.surfaceSubtle)
        .clipShape(RoundedRectangle(cornerRadius: QRadius.md))
    }
}
