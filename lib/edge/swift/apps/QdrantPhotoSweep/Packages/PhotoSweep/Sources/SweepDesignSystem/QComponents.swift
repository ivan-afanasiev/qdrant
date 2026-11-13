#if os(iOS)
import SwiftUI

// MARK: - Primary Button

public struct QPrimaryButtonStyle: ButtonStyle {
    public func makeBody(configuration: Configuration) -> some View {
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

public struct QSecondaryButtonStyle: ButtonStyle {
    public func makeBody(configuration: Configuration) -> some View {
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

public struct QDestructiveButtonStyle: ButtonStyle {
    public func makeBody(configuration: Configuration) -> some View {
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

public struct QGhostButtonStyle: ButtonStyle {
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(QTypography.bodyMedium)
            .foregroundStyle(QColors.textSecondary)
            .opacity(configuration.isPressed ? 0.6 : 1.0)
    }
}

extension ButtonStyle where Self == QPrimaryButtonStyle {
    public static var qPrimary: QPrimaryButtonStyle { QPrimaryButtonStyle() }
}

extension ButtonStyle where Self == QSecondaryButtonStyle {
    public static var qSecondary: QSecondaryButtonStyle { QSecondaryButtonStyle() }
}

extension ButtonStyle where Self == QDestructiveButtonStyle {
    public static var qDestructive: QDestructiveButtonStyle { QDestructiveButtonStyle() }
}

extension ButtonStyle where Self == QGhostButtonStyle {
    public static var qGhost: QGhostButtonStyle { QGhostButtonStyle() }
}

// MARK: - Status Badge

public struct QStatusBadge: View {
    public enum Variant {
        case success, warning, error, info
    }

    let icon: String
    let variant: Variant

    public init(icon: String, variant: Variant) {
        self.icon = icon
        self.variant = variant
    }

    public var body: some View {
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

public struct QCard<Content: View>: View {
    let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .background(QColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: QRadius.lg))
            .qShadow(QShadow.md)
    }
}

// MARK: - Status Icon View

public struct QStatusIcon: View {
    let systemName: String
    let size: CGFloat
    let color: Color

    public init(_ systemName: String, size: CGFloat = QSize.iconLarge, color: Color) {
        self.systemName = systemName
        self.size = size
        self.color = color
    }

    public var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size))
            .foregroundStyle(color)
    }
}

#endif
