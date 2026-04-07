import SwiftUI

struct BannerCard: View {
    enum Style {
        case primary, secondary
    }

    let icon: String
    let iconColor: Color
    let message: String
    let buttonTitle: LocalizedStringKey
    let buttonIcon: String
    let buttonStyle: Style
    let action: () -> Void

    var body: some View {
        VStack(spacing: QSpacing.sm) {
            HStack(spacing: QSpacing.sm) {
                Image(systemName: icon)
                    .foregroundStyle(iconColor)
                Text(message)
                    .font(QTypography.bodyMedium)
                Spacer()
            }

            actionButton
        }
        .padding()
        .background(QColors.surfaceSubtle)
        .clipShape(RoundedRectangle(cornerRadius: QRadius.md))
    }

    @ViewBuilder
    private var actionButton: some View {
        switch buttonStyle {
        case .primary:
            Button(action: action) {
                Label(buttonTitle, systemImage: buttonIcon)
            }
            .buttonStyle(.qPrimary)
        case .secondary:
            Button(action: action) {
                Label(buttonTitle, systemImage: buttonIcon)
            }
            .buttonStyle(.qSecondary)
        }
    }
}
