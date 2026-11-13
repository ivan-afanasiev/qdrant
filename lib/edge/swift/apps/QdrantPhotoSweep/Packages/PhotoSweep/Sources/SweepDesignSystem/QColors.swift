#if os(iOS)
import SwiftUI

public enum QColors {
    // MARK: - Brand

    public static let amaranth = Color(hex: 0xDC244C)
    public static let violet = Color(hex: 0x8547FF)
    public static let blue = Color(hex: 0x2F6FF0)
    public static let teal = Color(hex: 0x038585)
    public static let brandBlack = Color(hex: 0x090E1A)
    public static let brandWhite = Color(hex: 0xFFFFFF)

    // MARK: - Semantic

    public static let primary = amaranth
    public static let primaryVariant = Color(hex: 0xB81D3E)
    public static let secondary = violet
    public static let accent = blue

    public static let success = teal
    public static let warning = Color.adaptive(light: 0xE6A817, dark: 0xF0B429)
    public static let error = amaranth
    public static let destructive = amaranth

    // MARK: - Text

    public static let textPrimary = Color.adaptive(light: 0x090E1A, dark: 0xF0F1F5)
    public static let textSecondary = Color.adaptive(light: 0x5A6175, dark: 0xA0A8BC)
    public static let textTertiary = Color.adaptive(light: 0x8E95A7, dark: 0x6B7185)
    public static let textOnPrimary = brandWhite

    // MARK: - Surface

    public static let surfaceBackground = Color.adaptive(light: 0xF7F8FA, dark: 0x0E1117)
    public static let surface = Color.adaptive(light: 0xFFFFFF, dark: 0x161B22)
    public static let surfaceElevated = Color.adaptive(light: 0xFFFFFF, dark: 0x1C2128)
    public static let surfaceSubtle = Color.adaptive(light: 0xF0F1F5, dark: 0x1C2128)
    public static let surfaceMuted = Color.adaptive(light: 0xE4E6ED, dark: 0x272D36)

    // MARK: - Border & Divider

    public static let border = Color.adaptive(light: 0xDDE0E8, dark: 0x30363D)
    public static let borderSubtle = Color.adaptive(light: 0xECEDF2, dark: 0x21262D)

    // MARK: - Overlay

    public static let overlayLight = Color.black.opacity(0.06)
    public static let overlayMedium = Color.black.opacity(0.12)
    public static let overlayDark = Color.black.opacity(0.4)
}

// MARK: - Color Extension

extension Color {
    public init(hex: UInt, opacity: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }

    public static func adaptive(light: UInt, dark: UInt) -> Color {
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

#endif
