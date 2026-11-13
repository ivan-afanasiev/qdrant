import Foundation

/// Photos local identifier of an asset. Stable across launches; never a vector point ID.
public struct AssetID: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String { rawValue }

    public static func < (lhs: AssetID, rhs: AssetID) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Durable identity of a review group; survives membership revisions.
public struct GroupID: Hashable, Sendable {
    public let rawValue: UUID

    public init(_ rawValue: UUID) {
        self.rawValue = rawValue
    }
}

/// Identity of a recoverable external operation such as a deletion request.
public struct OperationID: Hashable, Sendable {
    public let rawValue: UUID

    public init(_ rawValue: UUID) {
        self.rawValue = rawValue
    }
}

/// Identity of one vectorization pass over a captured work set.
public struct VectorizationPassID: Hashable, Sendable {
    public let rawValue: UUID

    public init(_ rawValue: UUID) {
        self.rawValue = rawValue
    }
}

/// Monotonic discovery revision; threshold changes and rescans create a new one.
public struct DiscoveryRevision: Hashable, Comparable, Sendable {
    public let rawValue: Int

    public init(_ rawValue: Int) {
        self.rawValue = rawValue
    }

    public func next() -> DiscoveryRevision {
        DiscoveryRevision(rawValue + 1)
    }

    public static func < (lhs: DiscoveryRevision, rhs: DiscoveryRevision) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Monotonic index generation; a compatibility transition publishes a new one.
public struct IndexGeneration: Hashable, Comparable, Sendable {
    public let rawValue: Int

    public init(_ rawValue: Int) {
        self.rawValue = rawValue
    }

    public func next() -> IndexGeneration {
        IndexGeneration(rawValue + 1)
    }

    public static func < (lhs: IndexGeneration, rhs: IndexGeneration) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Monotonic membership revision of one group; changes even when the member count does not.
public struct MembershipRevision: Hashable, Comparable, Sendable {
    public let rawValue: Int

    public init(_ rawValue: Int) {
        self.rawValue = rawValue
    }

    public func next() -> MembershipRevision {
        MembershipRevision(rawValue + 1)
    }

    public static func < (lhs: MembershipRevision, rhs: MembershipRevision) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Source of new UUIDs. Inject a deterministic generator in tests.
public protocol IDGenerating: Sendable {
    func makeUUID() -> UUID
}

public struct SystemIDGenerator: IDGenerating {
    public init() {}

    public func makeUUID() -> UUID {
        UUID()
    }
}
