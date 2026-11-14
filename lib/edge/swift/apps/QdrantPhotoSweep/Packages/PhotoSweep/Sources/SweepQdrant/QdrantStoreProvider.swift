import Foundation
import SweepDomain

/// Single owner of the open Qdrant shard. Each index generation lives in its own
/// directory (`<root>/g<generation>`), so changing the embedding model opens a new
/// shard instead of deleting the current one in place.
public actor QdrantStoreProvider: VectorStoreProviding {
    private let root: URL
    private var current: (generation: IndexGeneration, dimensions: Int, store: QdrantVectorStore)?

    public init(root: URL) {
        self.root = root
    }

    public func store(for generation: IndexGeneration, dimensions: Int) async throws(AdapterError) -> any VectorStoring {
        if let current, current.generation == generation {
            guard current.dimensions == dimensions else {
                throw .vectorStore("Generation \(generation.rawValue) uses \(current.dimensions) dimensions, not \(dimensions)")
            }
            return current.store
        }
        await current?.store.close()
        let store = QdrantVectorStore(path: directory(for: generation).path, dimensions: dimensions)
        current = (generation, dimensions, store)
        return store
    }

    public func removeStores(olderThan generation: IndexGeneration) async {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: root.path) else { return }
        for name in names {
            guard name.hasPrefix("g"), let value = Int(name.dropFirst()), value < generation.rawValue else { continue }
            if let current, current.generation.rawValue == value {
                await current.store.close()
                self.current = nil
            }
            try? FileManager.default.removeItem(at: root.appending(path: name, directoryHint: .isDirectory))
        }
    }

    func directory(for generation: IndexGeneration) -> URL {
        root.appending(path: "g\(generation.rawValue)", directoryHint: .isDirectory)
    }
}
