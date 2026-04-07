import Foundation
import os

enum AppLog {
    static let home = Logger(subsystem: Bundle.main.bundleIdentifier ?? "PhotoSweep", category: "Home")
    static let scan = Logger(subsystem: Bundle.main.bundleIdentifier ?? "PhotoSweep", category: "Scan")
    static let review = Logger(subsystem: Bundle.main.bundleIdentifier ?? "PhotoSweep", category: "Review")
    static let settings = Logger(subsystem: Bundle.main.bundleIdentifier ?? "PhotoSweep", category: "Settings")
    static let background = Logger(subsystem: Bundle.main.bundleIdentifier ?? "PhotoSweep", category: "Background")
}
