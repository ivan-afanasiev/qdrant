import Foundation

/// Everything that must match for a stored vector to be comparable with new ones.
/// Dimension count alone is not sufficient.
public struct EmbeddingCompatibility: Hashable, Sendable {
    public let model: String
    public let modelRevision: Int
    public let preprocessing: String
    public let dimensions: Int

    public init(model: String, modelRevision: Int, preprocessing: String, dimensions: Int) {
        self.model = model
        self.modelRevision = modelRevision
        self.preprocessing = preprocessing
        self.dimensions = dimensions
    }
}

/// Opaque token identifying an asset's content version (for example its modification date).
public struct AssetContentRevision: Hashable, Sendable {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

/// Metadata describing a vector previously written for an asset.
public struct StoredVector: Hashable, Sendable {
    public let assetID: AssetID
    public let contentRevision: AssetContentRevision
    public let compatibility: EmbeddingCompatibility
    public let generation: IndexGeneration
    /// True only after the metadata commit that follows the vector write.
    /// Point existence in the vector store alone is not successful vectorization.
    public let isCommitted: Bool

    public init(
        assetID: AssetID,
        contentRevision: AssetContentRevision,
        compatibility: EmbeddingCompatibility,
        generation: IndexGeneration,
        isCommitted: Bool
    ) {
        self.assetID = assetID
        self.contentRevision = contentRevision
        self.compatibility = compatibility
        self.generation = generation
        self.isCommitted = isCommitted
    }
}

public enum VectorReuseDecision: Equatable, Sendable {
    case reuse
    case revectorize(Reason)

    public enum Reason: Equatable, Sendable {
        case missing
        case uncommitted
        case contentChanged
        case incompatible
        case staleGeneration
    }
}

public enum VectorReusePolicy {
    /// Decides whether an existing vector can be reused for the current pass.
    public static func decide(
        existing: StoredVector?,
        currentRevision: AssetContentRevision,
        compatibility: EmbeddingCompatibility,
        generation: IndexGeneration
    ) -> VectorReuseDecision {
        guard let existing else { return .revectorize(.missing) }
        guard existing.isCommitted else { return .revectorize(.uncommitted) }
        guard existing.compatibility == compatibility else { return .revectorize(.incompatible) }
        guard existing.generation == generation else { return .revectorize(.staleGeneration) }
        guard existing.contentRevision == currentRevision else { return .revectorize(.contentChanged) }
        return .reuse
    }
}
