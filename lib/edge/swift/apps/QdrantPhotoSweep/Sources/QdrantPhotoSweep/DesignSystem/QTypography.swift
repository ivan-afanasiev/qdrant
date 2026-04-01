import SwiftUI

enum QTypography {
    // MARK: - Display

    static let displayLarge = Font.system(size: 64, weight: .bold)
    static let displayMedium = Font.system(size: 48, weight: .bold)

    // MARK: - Title

    static let titleLarge = Font.title.bold()
    static let titleMedium = Font.title2.bold()
    static let titleSmall = Font.title3.bold()

    // MARK: - Body

    static let bodyLarge = Font.headline
    static let bodyMedium = Font.subheadline
    static let bodySmall = Font.footnote

    // MARK: - Caption

    static let caption = Font.caption
    static let captionSmall = Font.caption2

    // MARK: - Monospaced (for numeric displays)

    static let numericLarge = Font.title.bold().monospacedDigit()
    static let numericMedium = Font.headline.monospacedDigit()
    static let numericSmall = Font.caption.monospacedDigit()
    static let numericTiny = Font.caption2.bold().monospacedDigit()
}
