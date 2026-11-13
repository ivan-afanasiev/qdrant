#if os(iOS)
import SwiftUI

// MARK: - Animation Presets

public enum QAnimation {
    public static let springDefault = Animation.spring(response: 0.4, dampingFraction: 0.8)
    public static let smooth = Animation.easeInOut(duration: 0.3)
    public static let quick = Animation.easeInOut(duration: 0.15)
}

#endif
