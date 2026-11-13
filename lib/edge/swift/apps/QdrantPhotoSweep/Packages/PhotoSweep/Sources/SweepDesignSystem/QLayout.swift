#if os(iOS)
import SwiftUI

// MARK: - Spacing

public enum QSpacing {
    public static let xxxs: CGFloat = 2
    public static let xxs: CGFloat = 4
    public static let xs: CGFloat = 8
    public static let sm: CGFloat = 12
    public static let md: CGFloat = 16
    public static let lg: CGFloat = 20
    public static let xl: CGFloat = 24
    public static let xxl: CGFloat = 32
    public static let xxxl: CGFloat = 48
}

// MARK: - Corner Radius

public enum QRadius {
    public static let xs: CGFloat = 6
    public static let sm: CGFloat = 8
    public static let md: CGFloat = 12
    public static let lg: CGFloat = 16
    public static let xl: CGFloat = 20
    public static let pill: CGFloat = 999
}

// MARK: - Shadow

public enum QShadow {
    public struct Properties: Sendable {
        let color: Color
        let radius: CGFloat
        let x: CGFloat
        let y: CGFloat
    }

    public static let sm = Properties(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
    public static let md = Properties(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
    public static let lg = Properties(color: .black.opacity(0.15), radius: 16, x: 0, y: 8)
}

// MARK: - Size

public enum QSize {
    public static let iconSmall: CGFloat = 20
    public static let iconMedium: CGFloat = 32
    public static let iconLarge: CGFloat = 48
    public static let iconXLarge: CGFloat = 64

    public static let progressRing: CGFloat = 160
    public static let progressStroke: CGFloat = 8

    public static let thumbnailRequest = CGSize(width: 300, height: 300)
    public static let cardImageMinHeight: CGFloat = 200
}

// MARK: - View Modifier Extensions

extension View {
    public func qShadow(_ shadow: QShadow.Properties) -> some View {
        self.shadow(color: shadow.color, radius: shadow.radius, x: shadow.x, y: shadow.y)
    }
}

#endif
