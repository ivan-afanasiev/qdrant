import Foundation
import Testing
import SweepDomain
import SweepQdrant

struct QdrantStoreProviderTests {
    @Test func generationsAreIsolatedAndOldOnesRemovable() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "QdrantProvider-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let provider = QdrantStoreProvider(root: root)
        let id = UUID().uuidString.lowercased()

        let first = try await provider.store(for: IndexGeneration(1), dimensions: 3)
        try await first.upsert(points: [VectorPoint(id: id, vector: [1, 0, 0], payloadJson: "{}")])
        let same = try await provider.store(for: IndexGeneration(1), dimensions: 3)
        #expect(try await same.count() == 1)

        // A new generation (for example a model change) starts empty, with different dimensions.
        let second = try await provider.store(for: IndexGeneration(2), dimensions: 4)
        #expect(try await second.count() == 0)
        #expect(FileManager.default.fileExists(atPath: root.appending(path: "g1").path))

        await provider.removeStores(olderThan: IndexGeneration(2))
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: "g1").path))
        #expect(try await provider.store(for: IndexGeneration(2), dimensions: 4).count() == 0)
    }

    @Test func dimensionMismatchWithinGenerationIsRejected() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "QdrantProvider-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let provider = QdrantStoreProvider(root: root)
        _ = try await provider.store(for: IndexGeneration(1), dimensions: 3)
        await #expect(throws: AdapterError.self) {
            _ = try await provider.store(for: IndexGeneration(1), dimensions: 4)
        }
    }
}
