import SwiftUI

// MARK: - Animation Presets

enum QAnimation {
    static let springDefault = Animation.spring(response: 0.4, dampingFraction: 0.8)
    static let smooth = Animation.easeInOut(duration: 0.3)
    static let quick = Animation.easeInOut(duration: 0.15)
}
