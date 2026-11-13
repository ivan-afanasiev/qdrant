import Foundation
import Testing
import SweepDomain

/// Drives an expansion to completion against an in-memory similarity graph.
private func expand(
    _ expansion: inout ComponentExpansion,
    graph: [AssetID: [Neighbor]],
    pageSize: Int = .max,
    isEligible: (AssetID) -> Bool = { _ in true }
) throws {
    while let query = expansion.nextQuery {
        let neighbors = graph[query, default: []]
        var start = 0
        repeat {
            let end = min(start + pageSize, neighbors.count)
            try expansion.absorb(Array(neighbors[start..<end]), for: query, isLastPage: end == neighbors.count, isEligible: isEligible)
            start = end
        } while start < neighbors.count
    }
}

/// Undirected graph from scored edges; all assets dated inside the January scope unless overridden.
private func graph(_ edges: [(String, String, Float)], dates: [String: Date?] = [:]) -> [AssetID: [Neighbor]] {
    var result: [AssetID: [Neighbor]] = [:]
    for (lhs, rhs, score) in edges {
        result[asset(lhs), default: []].append(Neighbor(asset: asset(rhs), creationDate: dates[rhs] ?? date(10), score: score))
        result[asset(rhs), default: []].append(Neighbor(asset: asset(lhs), creationDate: dates[lhs] ?? date(10), score: score))
    }
    return result
}

@Suite struct ComponentExpansionTests {
    func start(_ seed: String = "a", seedDate: Date? = date(10), at value: Float = 0.9) throws -> ComponentExpansion {
        try #require(ComponentExpansion(
            seed: asset(seed), seedCreationDate: seedDate, scope: januaryScope,
            threshold: try threshold(value), generation: IndexGeneration(1)
        ))
    }

    @Test func chainJoinsAssetsThatDoNotMatchDirectly() throws {
        var expansion = try start()
        try expand(&expansion, graph: graph([("a", "b", 0.95), ("b", "c", 0.95), ("a", "c", 0.5)]))
        #expect(expansion.isComplete)
        #expect(expansion.members == [asset("a"), asset("b"), asset("c")])
    }

    @Test func thresholdBoundaryIsInclusive() throws {
        var expansion = try start(at: 0.9)
        try expand(&expansion, graph: graph([("a", "b", 0.9), ("a", "c", 0.8999)]))
        #expect(expansion.members == [asset("a"), asset("b")])
    }

    @Test func invalidThresholdsAreRejected() {
        #expect(SimilarityThreshold(-0.1) == nil)
        #expect(SimilarityThreshold(1.01) == nil)
        #expect(SimilarityThreshold(.nan) == nil)
        #expect(SimilarityThreshold(1) != nil)
    }

    @Test func moreThanTenMatchesAreAllIncluded() throws {
        var expansion = try start()
        let edges = (0..<25).map { ("a", "n\($0)", Float(0.95)) }
        try expand(&expansion, graph: graph(edges), pageSize: 10)
        #expect(expansion.members.count == 26)
    }

    @Test func giantChainIsExpandedCompletelyInOrder() throws {
        let length = 5_000
        let edges = (0..<length).map { ("c\($0)", "c\($0 + 1)", Float(0.95)) }
        var expansion = try start("c0")
        try expand(&expansion, graph: graph(edges))
        #expect(expansion.members.count == length + 1)
        #expect(expansion.isGroup)
    }

    @Test func seedOutsideScopeIsRejected() throws {
        let outside = ComponentExpansion(
            seed: asset("a"), seedCreationDate: date(40), scope: januaryScope,
            threshold: try threshold(0.9), generation: IndexGeneration(1)
        )
        #expect(outside == nil)
        let undated = ComponentExpansion(
            seed: asset("a"), seedCreationDate: nil, scope: januaryScope,
            threshold: try threshold(0.9), generation: IndexGeneration(1)
        )
        #expect(undated == nil)
    }

    @Test func candidateOutsideScopeNeverBridgesChain() throws {
        var expansion = try start()
        try expand(&expansion, graph: graph([("a", "x", 0.99), ("x", "c", 0.99)], dates: ["x": date(45)]))
        #expect(expansion.members == [asset("a")])
        #expect(!expansion.isGroup)
    }

    @Test func ineligibleAssetsAreExcluded() throws {
        var expansion = try start()
        try expand(&expansion, graph: graph([("a", "b", 0.95), ("a", "uncommitted", 0.95)])) { $0 != asset("uncommitted") }
        #expect(expansion.members == [asset("a"), asset("b")])
    }

    @Test func selfMatchesAndDuplicatesDoNotGrowFrontier() throws {
        var expansion = try start()
        let neighbors = [
            Neighbor(asset: asset("a"), creationDate: date(10), score: 1),
            Neighbor(asset: asset("b"), creationDate: date(10), score: 0.95),
            Neighbor(asset: asset("b"), creationDate: date(10), score: 0.95),
        ]
        try expansion.absorb(neighbors, for: asset("a"), isLastPage: true)
        #expect(Array(expansion.frontier) == [asset("b")])
    }

    @Test func queryIsConsumedOnlyAfterLastPage() throws {
        var expansion = try start()
        try expansion.absorb([Neighbor(asset: asset("b"), creationDate: date(10), score: 0.95)], for: asset("a"), isLastPage: false)
        #expect(expansion.nextQuery == asset("a"))
        #expect(!expansion.isComplete)
        try expansion.absorb([], for: asset("a"), isLastPage: true)
        #expect(expansion.nextQuery == asset("b"))
    }

    @Test func resumedStateContinuesWhereInterruptedStateStopped() throws {
        let edges = graph([("a", "b", 0.95), ("b", "c", 0.95), ("c", "d", 0.95)])
        var interrupted = try start()
        try interrupted.absorb(edges[asset("a"), default: []], for: asset("a"), isLastPage: true)
        var resumed = interrupted
        try expand(&resumed, graph: edges)
        var uninterrupted = try start()
        try expand(&uninterrupted, graph: edges)
        #expect(resumed.members == uninterrupted.members)
    }

    @Test func resultsForWrongQueryAreRejected() throws {
        var expansion = try start()
        #expect(throws: ComponentExpansion.AbsorbError.unexpectedQuery(expected: asset("a"), received: asset("z"))) {
            try expansion.absorb([], for: asset("z"), isLastPage: true)
        }
    }
}

@Suite struct DiscoveryStatusPolicyTests {
    let buffer = ReviewBufferPolicy.default

    func inputs(
        gate: Bool = true,
        presence: AppPresence = .foreground,
        ready: Int = 0,
        exhausted: Bool = false,
        failure: String? = nil
    ) -> DiscoveryInputs {
        DiscoveryInputs(isInitialGateOpen: gate, presence: presence, readyCount: ready, isSeedCursorExhausted: exhausted, failure: failure)
    }

    @Test func waitsForInitialPass() {
        #expect(DiscoveryPolicy.status(inputs(gate: false), buffer: buffer) == .waitingForInitialPass)
    }

    @Test func neverSearchesInBackground() {
        #expect(DiscoveryPolicy.status(inputs(presence: .background), buffer: buffer) == .suspended)
        #expect(!DiscoveryPolicy.shouldSearch(inputs(presence: .background), buffer: buffer))
    }

    @Test func searchesUntilBufferIsFull() {
        #expect(DiscoveryPolicy.shouldSearch(inputs(ready: 2), buffer: buffer))
        #expect(DiscoveryPolicy.status(inputs(ready: 3), buffer: buffer) == .bufferReady)
    }

    @Test func emptyBufferIsNotExhaustion() {
        #expect(DiscoveryPolicy.status(inputs(ready: 0, exhausted: false), buffer: buffer) == .searching)
        #expect(DiscoveryPolicy.status(inputs(ready: 0, exhausted: true), buffer: buffer) == .exhausted)
    }

    @Test func fullBufferTakesPrecedenceOverExhaustion() {
        #expect(DiscoveryPolicy.status(inputs(ready: 3, exhausted: true), buffer: buffer) == .bufferReady)
    }

    @Test func failureIsReported() {
        #expect(DiscoveryPolicy.status(inputs(failure: "store"), buffer: buffer) == .failed("store"))
    }

    @Test func capacityIsLimitedToTwoOrThree() throws {
        #expect(ReviewBufferPolicy(capacity: 1) == nil)
        #expect(ReviewBufferPolicy(capacity: 4) == nil)
        let two = try #require(ReviewBufferPolicy(capacity: 2))
        #expect(DiscoveryPolicy.status(inputs(ready: 2), buffer: two) == .bufferReady)
    }
}
