import Foundation

/// Date-range choices. A preset is a rolling window: it is resolved again at the start of
/// every vectorization pass, and its end is open so newly taken photos stay in scope.
public enum DateScopePreset: String, CaseIterable, Equatable, Sendable {
    case lastWeek
    case lastMonth
    case last3Months
    case last6Months
    case lastYear
    case allTime

    public static let `default` = DateScopePreset.allTime

    public func range(endingAt now: Date, calendar: Calendar = .current) -> DateRange {
        let start: Date? = switch self {
        case .lastWeek: calendar.date(byAdding: .day, value: -7, to: now)
        case .lastMonth: calendar.date(byAdding: .month, value: -1, to: now)
        case .last3Months: calendar.date(byAdding: .month, value: -3, to: now)
        case .last6Months: calendar.date(byAdding: .month, value: -6, to: now)
        case .lastYear: calendar.date(byAdding: .year, value: -1, to: now)
        case .allTime: nil
        }
        return DateRange(start: start ?? .distantPast, end: .distantFuture)
    }
}

/// Similarity choices offered instead of a raw threshold.
public enum SimilarityPreset: String, CaseIterable, Equatable, Sendable {
    case strict
    case balanced
    case loose

    public static let `default` = SimilarityPreset.balanced

    public var threshold: SimilarityThreshold {
        switch self {
        case .strict: SimilarityThreshold(0.96) ?? .standard
        case .balanced: .standard
        case .loose: SimilarityThreshold(0.85) ?? .standard
        }
    }

    /// The preset whose threshold equals `threshold`, if any.
    public init?(threshold: SimilarityThreshold) {
        guard let match = Self.allCases.first(where: { $0.threshold == threshold }) else { return nil }
        self = match
    }
}
