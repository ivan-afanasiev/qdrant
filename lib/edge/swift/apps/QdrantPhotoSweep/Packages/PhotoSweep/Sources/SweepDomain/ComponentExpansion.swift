import Foundation

/// Cosine similarity threshold. A score equal to the threshold matches.
public struct SimilarityThreshold: Hashable, Sendable {
    public let value: Float

    /// Returns nil for values outside 0...1 or non-finite values.
    public init?(_ value: Float) {
        guard value.isFinite, (0...1).contains(value) else { return nil }
        self.value = value
    }

    public func matches(_ score: Float) -> Bool {
        score >= value
    }
}

/// A search hit for the asset being expanded.
public struct Neighbor: Equatable, Sendable {
    public let asset: AssetID
    public let creationDate: Date?
    public let score: Float

    public init(asset: AssetID, creationDate: Date?, score: Float) {
        self.asset = asset
        self.creationDate = creationDate
        self.score = score
    }
}

/// Lazily expands one connected component from a seed, pinned to an index generation.
///
/// Members are connected through chains of matches (A–B and B–C join A and C even if
/// A–C does not match), so a group does not imply all-pairs similarity. Both seed and
/// candidates must be inside the date scope; out-of-scope assets never bridge a chain.
/// Results may arrive in pages; a frontier asset is consumed only after its last page,
/// so the state can be persisted and resumed without losing an in-flight query.
public struct ComponentExpansion: Equatable, Sendable {
    public enum AbsorbError: Error, Equatable, Sendable {
        /// Results were for an asset other than `nextQuery`.
        case unexpectedQuery(expected: AssetID?, received: AssetID)
    }

    public let seed: AssetID
    public let scope: DateRange
    public let threshold: SimilarityThreshold
    public let generation: IndexGeneration
    public private(set) var members: Set<AssetID>
    /// Discovered assets in visit order; entries before `head` have been fully queried.
    private var queue: [AssetID]
    private var head = 0

    /// Returns nil when the seed is outside the scope.
    public init?(
        seed: AssetID,
        seedCreationDate: Date?,
        scope: DateRange,
        threshold: SimilarityThreshold,
        generation: IndexGeneration
    ) {
        guard scope.contains(seedCreationDate) else { return nil }
        self.seed = seed
        self.scope = scope
        self.threshold = threshold
        self.generation = generation
        self.members = [seed]
        self.queue = [seed]
    }

    /// The asset whose neighborhood must be retrieved next, or nil when expansion is complete.
    public var nextQuery: AssetID? { head < queue.count ? queue[head] : nil }

    /// Assets still waiting to be queried, including `nextQuery`.
    public var frontier: ArraySlice<AssetID> { queue[head...] }

    /// Complete for the pinned generation; only then may the component be published.
    public var isComplete: Bool { head == queue.count }

    /// A component with fewer than two members is not a reviewable group.
    public var isGroup: Bool { members.count >= 2 }

    /// Absorbs one page of neighbors for `nextQuery`.
    /// - Parameters:
    ///   - isLastPage: true when retrieval for this query is complete.
    ///   - isEligible: excludes assets that are not committed in the pinned generation,
    ///     deferred, or otherwise unavailable to this discovery revision.
    public mutating func absorb(
        _ neighbors: [Neighbor],
        for query: AssetID,
        isLastPage: Bool,
        isEligible: (AssetID) -> Bool = { _ in true }
    ) throws(AbsorbError) {
        guard query == nextQuery else {
            throw .unexpectedQuery(expected: nextQuery, received: query)
        }
        for neighbor in neighbors where !members.contains(neighbor.asset) {
            guard threshold.matches(neighbor.score),
                  scope.contains(neighbor.creationDate),
                  isEligible(neighbor.asset) else { continue }
            members.insert(neighbor.asset)
            queue.append(neighbor.asset)
        }
        if isLastPage {
            head += 1
        }
    }
}
