import SwiftUI

// MARK: - Spacing

enum QSpacing {
    static let xxxs: CGFloat = 2
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 20
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
    static let xxxl: CGFloat = 48
}

// MARK: - Corner Radius

enum QRadius {
    static let xs: CGFloat = 6
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let pill: CGFloat = 999
}

// MARK: - Shadow

enum QShadow {
    struct Properties {
        let color: Color
        let radius: CGFloat
        let x: CGFloat
        let y: CGFloat
    }

    static let sm = Properties(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
    static let md = Properties(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
    static let lg = Properties(color: .black.opacity(0.15), radius: 16, x: 0, y: 8)
}

// MARK: - Size

enum QSize {
    static let iconSmall: CGFloat = 20
    static let iconMedium: CGFloat = 32
    static let iconLarge: CGFloat = 48
    static let iconXLarge: CGFloat = 64

    static let progressRing: CGFloat = 160
    static let progressStroke: CGFloat = 8

    static let thumbnailRequest = CGSize(width: 300, height: 300)
    static let cardImageMinHeight: CGFloat = 200
}

// MARK: - View Modifier Extensions

extension View {
    func qShadow(_ shadow: QShadow.Properties) -> some View {
        self.shadow(color: shadow.color, radius: shadow.radius, x: shadow.x, y: shadow.y)
    }
}
