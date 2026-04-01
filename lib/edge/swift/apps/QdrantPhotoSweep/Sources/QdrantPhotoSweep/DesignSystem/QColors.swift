import SwiftUI

enum QColors {
    // MARK: - Brand

    static let amaranth = Color(hex: 0xDC244C)
    static let violet = Color(hex: 0x8547FF)
    static let blue = Color(hex: 0x2F6FF0)
    static let teal = Color(hex: 0x038585)
    static let brandBlack = Color(hex: 0x090E1A)
    static let brandWhite = Color(hex: 0xFFFFFF)

    // MARK: - Semantic

    static let primary = amaranth
    static let primaryVariant = Color(hex: 0xB81D3E)
    static let secondary = violet
    static let accent = blue

    static let success = teal
    static let warning = Color.adaptive(light: 0xE6A817, dark: 0xF0B429)
    static let error = amaranth
    static let destructive = amaranth

    // MARK: - Text

    static let textPrimary = Color.adaptive(light: 0x090E1A, dark: 0xF0F1F5)
    static let textSecondary = Color.adaptive(light: 0x5A6175, dark: 0xA0A8BC)
    static let textTertiary = Color.adaptive(light: 0x8E95A7, dark: 0x6B7185)
    static let textOnPrimary = brandWhite

    // MARK: - Surface

    static let surfaceBackground = Color.adaptive(light: 0xF7F8FA, dark: 0x0E1117)
    static let surface = Color.adaptive(light: 0xFFFFFF, dark: 0x161B22)
    static let surfaceElevated = Color.adaptive(light: 0xFFFFFF, dark: 0x1C2128)
    static let surfaceSubtle = Color.adaptive(light: 0xF0F1F5, dark: 0x1C2128)
    static let surfaceMuted = Color.adaptive(light: 0xE4E6ED, dark: 0x272D36)

    // MARK: - Border & Divider

    static let border = Color.adaptive(light: 0xDDE0E8, dark: 0x30363D)
    static let borderSubtle = Color.adaptive(light: 0xECEDF2, dark: 0x21262D)

    // MARK: - Overlay

    static let overlayLight = Color.black.opacity(0.06)
    static let overlayMedium = Color.black.opacity(0.12)
    static let overlayDark = Color.black.opacity(0.4)
}

// MARK: - Color Extension

extension Color {
    init(hex: UInt, opacity: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }

    static func adaptive(light: UInt, dark: UInt) -> Color {
        Color(UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        })
    }
}
