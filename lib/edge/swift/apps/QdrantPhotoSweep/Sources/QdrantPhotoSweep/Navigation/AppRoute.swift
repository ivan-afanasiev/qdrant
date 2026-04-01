import Foundation

enum AppRoute: Hashable {
    case dateRangePicker
    case scan(DateRange)
    case review([DuplicateGroup])
    case settings
}

extension DateRange: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(start)
        hasher.combine(end)
    }
}
