import SwiftUI

@Observable
final class AppSettings {
    static let defaultSimilarityThreshold: Float = 0.92

    private let defaults = UserDefaults.standard

    var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: "hasCompletedOnboarding") }
    }

    var similarityThreshold: Float {
        didSet { defaults.set(similarityThreshold, forKey: "similarityThreshold") }
    }

    var scanPreset: DatePreset? {
        didSet {
            defaults.set(scanPreset?.rawValue, forKey: "scanPreset")
            if scanPreset != nil { isCustomRange = false }
        }
    }

    var customRangeStart: Date {
        didSet { defaults.set(customRangeStart, forKey: "customRangeStart") }
    }

    var customRangeEnd: Date {
        didSet { defaults.set(customRangeEnd, forKey: "customRangeEnd") }
    }

    var isCustomRange: Bool {
        didSet { defaults.set(isCustomRange, forKey: "isCustomRange") }
    }

    var currentDateRange: DateRange {
        switch isCustomRange {
        case true:
            DateRange(start: customRangeStart, end: customRangeEnd)
        case false:
            scanPreset?.dateRange ?? DatePreset.allTime.dateRange
        }
    }

    /// Bumped by Settings to signal ScanView should start a new scan with the current range.
    var rescanRequestId = UUID()

    func requestRescan() {
        rescanRequestId = UUID()
    }

    init() {
        let storedThreshold = defaults.float(forKey: "similarityThreshold")
        self.similarityThreshold = storedThreshold > 0 ? storedThreshold : Self.defaultSimilarityThreshold
        self.hasCompletedOnboarding = defaults.bool(forKey: "hasCompletedOnboarding")
        self.scanPreset = defaults.string(forKey: "scanPreset").flatMap(DatePreset.init(rawValue:)) ?? .allTime
        self.customRangeStart = (defaults.object(forKey: "customRangeStart") as? Date) ?? Calendar.current.date(byAdding: .month, value: -1, to: .now) ?? .now
        self.customRangeEnd = (defaults.object(forKey: "customRangeEnd") as? Date) ?? .now
        self.isCustomRange = defaults.bool(forKey: "isCustomRange")
    }
}
