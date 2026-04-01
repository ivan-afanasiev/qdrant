import SwiftUI

// MARK: - Primary Button

struct QPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(QTypography.bodyLarge)
            .frame(maxWidth: .infinity)
            .padding(.vertical, QSpacing.sm)
            .padding(.horizontal, QSpacing.md)
            .background(QColors.primary)
            .foregroundStyle(QColors.textOnPrimary)
            .clipShape(RoundedRectangle(cornerRadius: QRadius.md))
            .opacity(configuration.isPressed ? 0.85 : 1.0)
    }
}

// MARK: - Secondary Button

struct QSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(QTypography.bodyLarge)
            .frame(maxWidth: .infinity)
            .padding(.vertical, QSpacing.sm)
            .padding(.horizontal, QSpacing.md)
            .background(QColors.surfaceSubtle)
            .foregroundStyle(QColors.textPrimary)
            .clipShape(RoundedRectangle(cornerRadius: QRadius.md))
            .opacity(configuration.isPressed ? 0.85 : 1.0)
    }
}

// MARK: - Destructive Button

struct QDestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(QTypography.bodyLarge)
            .frame(maxWidth: .infinity)
            .padding(.vertical, QSpacing.sm)
            .padding(.horizontal, QSpacing.md)
            .background(QColors.destructive.opacity(0.12))
            .foregroundStyle(QColors.destructive)
            .clipShape(RoundedRectangle(cornerRadius: QRadius.md))
            .opacity(configuration.isPressed ? 0.85 : 1.0)
    }
}

// MARK: - Ghost Button

struct QGhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(QTypography.bodyMedium)
            .foregroundStyle(QColors.textSecondary)
            .opacity(configuration.isPressed ? 0.6 : 1.0)
    }
}

extension ButtonStyle where Self == QPrimaryButtonStyle {
    static var qPrimary: QPrimaryButtonStyle { QPrimaryButtonStyle() }
}

extension ButtonStyle where Self == QSecondaryButtonStyle {
    static var qSecondary: QSecondaryButtonStyle { QSecondaryButtonStyle() }
}

extension ButtonStyle where Self == QDestructiveButtonStyle {
    static var qDestructive: QDestructiveButtonStyle { QDestructiveButtonStyle() }
}

extension ButtonStyle where Self == QGhostButtonStyle {
    static var qGhost: QGhostButtonStyle { QGhostButtonStyle() }
}

// MARK: - Status Badge

struct QStatusBadge: View {
    enum Variant {
        case success, warning, error, info
    }

    let icon: String
    let variant: Variant

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: QSize.iconXLarge))
            .foregroundStyle(color)
    }

    private var color: Color {
        switch variant {
        case .success: QColors.success
        case .warning: QColors.warning
        case .error: QColors.error
        case .info: QColors.accent
        }
    }
}

// MARK: - Card Container

struct QCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .background(QColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: QRadius.lg))
            .qShadow(QShadow.md)
    }
}

// MARK: - Status Icon View

struct QStatusIcon: View {
    let systemName: String
    let size: CGFloat
    let color: Color

    init(_ systemName: String, size: CGFloat = QSize.iconLarge, color: Color) {
        self.systemName = systemName
        self.size = size
        self.color = color
    }

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size))
            .foregroundStyle(color)
    }
}
