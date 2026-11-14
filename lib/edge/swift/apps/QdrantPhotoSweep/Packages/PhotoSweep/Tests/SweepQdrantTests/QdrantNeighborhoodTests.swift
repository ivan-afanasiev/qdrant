import Foundation
import Testing
import SweepDomain
import SweepQdrant

/// Validates the SDK capabilities discovery relies on (REV-04) against a real shard.
struct QdrantNeighborhoodTests {
    func makeStore() -> (QdrantVectorStore, URL) {
        let directory = FileManager.default.temporaryDirectory.appending(path: "QdrantNeighborhood-\(UUID().uuidString)", directoryHint: .isDirectory)
        return (QdrantVectorStore(path: directory.path, dimensions: 2), directory)
    }

    func point(_ index: Int, angle: Double, day: Int?) -> VectorPoint {
        VectorPoint(
            id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index))?.uuidString.lowercased() ?? UUID().uuidString.lowercased(),
            vector: [Float(cos(angle)), Float(sin(angle))],
            payloadJson: VectorPayload(asset: AssetID("a\(index)"), creationDate: day.map { Date(timeIntervalSince1970: Double($0) * 86_400) }).json
        )
    }

    @Test func pagingReturnsEveryMatchExactlyOnce() async throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        // 37 near-identical vectors (more than any single top-k page) plus 5 dissimilar ones.
        let similar = (0..<37).map { point($0, angle: Double($0) * 0.001, day: 1) }
        let dissimilar = (37..<42).map { point($0, angle: 1.5, day: 1) }
        try await store.upsert(points: similar + dissimilar)

        var seen: [String] = []
        var offset = 0
        while true {
            let page = try await store.searchPage(vector: [1, 0], threshold: 0.9, filter: nil, offset: offset, limit: 10)
            seen += page.map(\.id)
            offset += page.count
            if page.count < 10 { break }
        }
        #expect(seen.count == 37)
        #expect(Set(seen) == Set(similar.map(\.id)))
        await store.close()
    }

    @Test func dateFilterExcludesOutOfRangeAndUndatedPoints() async throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let inside = point(1, angle: 0, day: 10)
        let outside = point(2, angle: 0, day: 40)
        let undated = point(3, angle: 0, day: nil)
        try await store.upsert(points: [inside, outside, undated])

        let scope = DateRange(start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 30 * 86_400))
        let results = try await store.searchPage(vector: [1, 0], threshold: 0.5, filter: VectorSearchFilter(scope: scope), offset: 0, limit: 10)
        #expect(results.map(\.id) == [inside.id])
        #expect(VectorPayload.decode(results.first?.payloadJson)?.assetID == AssetID("a1"))
        await store.close()
    }

    @Test func thresholdIncludesEqualScores() async throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let identical = point(1, angle: 0, day: 1)
        try await store.upsert(points: [identical])
        // Cosine of a vector with itself is 1; a threshold of exactly 1 must still match.
        let results = try await store.searchPage(vector: identical.vector, threshold: 1, filter: nil, offset: 0, limit: 10)
        #expect(results.map(\.id) == [identical.id])
        await store.close()
    }

    @Test func storedVectorIsRetrievable() async throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let stored = point(1, angle: 0.3, day: 1)
        try await store.upsert(points: [stored])
        let vector = try #require(try await store.vector(id: stored.id))
        #expect(vector.count == 2)
        #expect(abs(vector[0] - stored.vector[0]) < 0.001)
        #expect(try await store.vector(id: UUID().uuidString.lowercased()) == nil)
        await store.close()
    }
}
