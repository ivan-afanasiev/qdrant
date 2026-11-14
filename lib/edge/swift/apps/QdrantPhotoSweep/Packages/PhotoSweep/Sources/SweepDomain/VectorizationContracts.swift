import Foundation

/// Emits when the photo library changes so new or edited photos are vectorized automatically.
public protocol PhotoLibraryChangeObserving: Sendable {
    /// Each call returns a new stream. Bursts of changes may be coalesced into one element.
    func libraryChanges() -> AsyncStream<Void>
}

/// The embedding model in use. Preprocessing is chosen by the vectorizer, not the model.
public struct EmbeddingModelDescriptor: Equatable, Sendable {
    public let model: String
    public let revision: Int
    public let dimensions: Int

    public init(model: String, revision: Int, dimensions: Int) {
        self.model = model
        self.revision = revision
        self.dimensions = dimensions
    }

    public func compatibility(preprocessing: String) -> EmbeddingCompatibility {
        EmbeddingCompatibility(model: model, modelRevision: revision, preprocessing: preprocessing, dimensions: dimensions)
    }
}

public protocol EmbeddingModelDescribing: Sendable {
    /// Describes the current model, probing it once if necessary.
    func modelDescriptor() async throws(AdapterError) -> EmbeddingModelDescriptor
}

/// Owner of the vector store shards. Each index generation has its own store, so a
/// compatibility change starts a fresh index instead of silently deleting the current one.
public protocol VectorStoreProviding: Sendable {
    /// The single shared store for `generation`, opening it on first use and closing other generations.
    func store(for generation: IndexGeneration, dimensions: Int) async throws(AdapterError) -> any VectorStoring
    /// Deletes stores of generations older than `generation`.
    func removeStores(olderThan generation: IndexGeneration) async
}
