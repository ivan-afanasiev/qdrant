import Foundation

extension DateRange {
    /// Scope membership used for both discovery seeds and candidates.
    /// Both bounds are inclusive, matching the Photos fetch predicate.
    /// Assets without a creation date are outside every scope.
    public func contains(_ date: Date?) -> Bool {
        guard let date else { return false }
        return start <= date && date <= end
    }
}
