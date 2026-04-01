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
    static let warning = Color(hex: 0xE6A817)
    static let error = amaranth
    static let destructive = amaranth

    // MARK: - Text

    static let textPrimary = brandBlack
    static let textSecondary = Color(hex: 0x5A6175)
    static let textTertiary = Color(hex: 0x8E95A7)
    static let textOnPrimary = brandWhite

    // MARK: - Surface

    static let surfaceBackground = Color(hex: 0xF7F8FA)
    static let surface = brandWhite
    static let surfaceElevated = brandWhite
    static let surfaceSubtle = Color(hex: 0xF0F1F5)
    static let surfaceMuted = Color(hex: 0xE4E6ED)

    // MARK: - Border & Divider

    static let border = Color(hex: 0xDDE0E8)
    static let borderSubtle = Color(hex: 0xECEDF2)

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
}
