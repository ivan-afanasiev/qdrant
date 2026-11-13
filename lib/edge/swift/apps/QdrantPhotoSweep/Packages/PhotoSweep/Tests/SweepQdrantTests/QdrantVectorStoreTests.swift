import Foundation
import Testing
import SweepDomain
import SweepQdrant

struct QdrantVectorStoreTests {
    @Test func persistsSearchesAndDeletesAcrossReopen() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = QdrantVectorStore(path: directory.path, dimensions: 3)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
        let id = UUID().uuidString.lowercased()
        try await store.upsert(points: [VectorPoint(id: id, vector: [1, 0, 0], payloadJson: "{}")])
        #expect(try await store.count() == 1)
        let matches = try await store.search(vector: [1, 0, 0], limit: 10, threshold: 0.9)
        #expect(matches.map(\.id) == [id])
        await store.close()
        let reopened = QdrantVectorStore(path: directory.path, dimensions: 3)
        #expect(try await reopened.count() == 1)
        try await reopened.delete(ids: [id])
        #expect(try await reopened.count() == 0)
        await reopened.close()
    }
}
