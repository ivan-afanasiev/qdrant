import Foundation

enum AppRoute: Hashable {
    case scan(DateRange, resumeSessionId: UUID? = nil)
    case review
    case settings
}

extension DateRange: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(start)
        hasher.combine(end)
    }
}
