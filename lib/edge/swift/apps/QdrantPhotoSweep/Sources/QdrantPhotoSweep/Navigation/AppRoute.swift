import Foundation

enum AppRoute: Hashable {
    case scan(DateRange)
    case review(threshold: Float)
    case settings
}

extension DateRange: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(start)
        hasher.combine(end)
    }
}
