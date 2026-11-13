#if os(iOS)
import SwiftUI

public enum QTypography {
    // MARK: - Display

    public static let displayLarge = Font.system(size: 64, weight: .bold)
    public static let displayMedium = Font.system(size: 48, weight: .bold)

    // MARK: - Title

    public static let titleLarge = Font.title.bold()
    public static let titleMedium = Font.title2.bold()
    public static let titleSmall = Font.title3.bold()

    // MARK: - Body

    public static let bodyLarge = Font.headline
    public static let bodyMedium = Font.subheadline
    public static let bodySmall = Font.footnote

    // MARK: - Caption

    public static let caption = Font.caption
    public static let captionSmall = Font.caption2

    // MARK: - Controls

    public static let iconButton = Font.system(size: 14, weight: .semibold)
    public static let dismissButton = Font.system(size: 16, weight: .bold)

    // MARK: - Monospaced (for numeric displays)

    public static let numericLarge = Font.title.bold().monospacedDigit()
    public static let numericMedium = Font.headline.monospacedDigit()
    public static let numericSmall = Font.caption.monospacedDigit()
    public static let numericTiny = Font.caption2.bold().monospacedDigit()
}

#endif
