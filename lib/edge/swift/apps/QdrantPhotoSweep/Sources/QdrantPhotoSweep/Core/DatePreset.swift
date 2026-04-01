import SwiftUI

enum DatePreset: String, CaseIterable, Identifiable {
    case lastWeek
    case lastMonth
    case last3Months
    case last6Months
    case lastYear
    case allTime

    var id: String { rawValue }

    var localizedName: LocalizedStringKey {
        switch self {
        case .lastWeek: L10n.lastWeek
        case .lastMonth: L10n.lastMonth
        case .last3Months: L10n.last3Months
        case .last6Months: L10n.last6Months
        case .lastYear: L10n.lastYear
        case .allTime: L10n.allTime
        }
    }

    var dateRange: DateRange {
        let now = Date.now
        let calendar = Calendar.current
        switch self {
        case .lastWeek:
            let start = calendar.date(byAdding: .weekOfYear, value: -1, to: now) ?? now
            return DateRange(start: start, end: now)
        case .lastMonth:
            let start = calendar.date(byAdding: .month, value: -1, to: now) ?? now
            return DateRange(start: start, end: now)
        case .last3Months:
            let start = calendar.date(byAdding: .month, value: -3, to: now) ?? now
            return DateRange(start: start, end: now)
        case .last6Months:
            let start = calendar.date(byAdding: .month, value: -6, to: now) ?? now
            return DateRange(start: start, end: now)
        case .lastYear:
            let start = calendar.date(byAdding: .year, value: -1, to: now) ?? now
            return DateRange(start: start, end: now)
        case .allTime:
            return .allTime
        }
    }
}
