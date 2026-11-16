#if os(iOS)
import SwiftUI

extension View {
    /// Shared Liquid Glass panel for floating controls and status cards. The system adapts
    /// the material for Reduce Transparency and Increase Contrast.
    public func qGlassPanel(cornerRadius: CGFloat = QRadius.lg) -> some View {
        padding(QSpacing.md)
            .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
    }
}
#endif
