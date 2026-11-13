import Foundation

/// Order of groups awaiting review.
///
/// Fresh groups are reviewed first, in discovery order; the first one is the current card.
/// Skip defers a group until every other eligible group has been reviewed, including groups
/// not yet discovered, so deferred groups are offered only after discovery is exhausted.
/// They then cycle in durable order without duplicate entries.
public struct ReviewQueue: Equatable, Sendable {
    public private(set) var fresh: [GroupID]
    public private(set) var deferred: [GroupID]

    public init(fresh: [GroupID] = [], deferred: [GroupID] = []) {
        self.fresh = fresh
        self.deferred = deferred
    }

    /// Ready groups counted against the review buffer, including the current card.
    public var readyCount: Int { fresh.count }

    /// Adds a newly published group. Returns false if it is already queued.
    @discardableResult
    public mutating func enqueueDiscovered(_ id: GroupID) -> Bool {
        guard !contains(id) else { return false }
        fresh.append(id)
        return true
    }

    /// The group to show now. Deferred groups appear only after true exhaustion;
    /// a temporarily empty buffer is not exhaustion.
    public func current(isDiscoveryExhausted: Bool) -> GroupID? {
        if let first = fresh.first { return first }
        return isDiscoveryExhausted ? deferred.first : nil
    }

    /// Moves a group to the end of the deferred order. Call only after the deferral is persisted.
    public mutating func skip(_ id: GroupID) {
        guard remove(id) else { return }
        deferred.append(id)
    }

    /// Removes a reviewed or retired group.
    public mutating func complete(_ id: GroupID) {
        remove(id)
    }

    /// Clears review order and skip deferrals (threshold change or rescan).
    public mutating func reset() {
        fresh.removeAll()
        deferred.removeAll()
    }

    public func contains(_ id: GroupID) -> Bool {
        fresh.contains(id) || deferred.contains(id)
    }

    @discardableResult
    private mutating func remove(_ id: GroupID) -> Bool {
        if let index = fresh.firstIndex(of: id) {
            fresh.remove(at: index)
            return true
        }
        if let index = deferred.firstIndex(of: id) {
            deferred.remove(at: index)
            return true
        }
        return false
    }
}
