import Foundation

public enum PersistenceError: Error, Equatable, Sendable {
    case storeUnavailable(String)
    case notFound(String)
    case invalidState(String)
    case saveFailed(String)
}

/// Vector store point identity. Assigned once per asset and never derived from the
/// asset identifier, so two assets can never collide on the same point.
public struct VectorPointID: Hashable, Sendable {
    public let rawValue: UUID

    public init(_ rawValue: UUID) {
        self.rawValue = rawValue
    }

    /// The string form used as the vector store point ID.
    public var storeKey: String { rawValue.uuidString.lowercased() }
}

/// An asset as reported by the photo library during reconciliation.
public struct DiscoveredAsset: Equatable, Sendable {
    public let id: AssetID
    public let creationDate: Date?
    public let contentRevision: AssetContentRevision

    public init(id: AssetID, creationDate: Date?, contentRevision: AssetContentRevision) {
        self.id = id
        self.creationDate = creationDate
        self.contentRevision = contentRevision
    }
}

public enum AssetVectorState: Equatable, Sendable {
    case pending
    /// Committed metadata for the vector currently stored at the asset's point ID.
    case vectorized(compatibility: EmbeddingCompatibility, generation: IndexGeneration, contentRevision: AssetContentRevision)
    case deferred(DeferralReason)
}

public struct AssetRecord: Equatable, Sendable {
    public let id: AssetID
    public let creationDate: Date?
    public let contentRevision: AssetContentRevision
    public let pointID: VectorPointID
    public let state: AssetVectorState

    public init(
        id: AssetID,
        creationDate: Date?,
        contentRevision: AssetContentRevision,
        pointID: VectorPointID,
        state: AssetVectorState
    ) {
        self.id = id
        self.creationDate = creationDate
        self.contentRevision = contentRevision
        self.pointID = pointID
        self.state = state
    }

    /// Input for `VectorReusePolicy`; nil unless committed metadata exists.
    public var storedVector: StoredVector? {
        guard case .vectorized(let compatibility, let generation, let revision) = state else { return nil }
        return StoredVector(
            assetID: id,
            contentRevision: revision,
            compatibility: compatibility,
            generation: generation,
            isCommitted: true
        )
    }
}

/// One vector about to be written for an asset.
public struct VectorWriteIntent: Equatable, Sendable {
    public let assetID: AssetID
    public let pointID: VectorPointID
    public let contentRevision: AssetContentRevision
    public let compatibility: EmbeddingCompatibility
    public let generation: IndexGeneration

    public init(
        assetID: AssetID,
        pointID: VectorPointID,
        contentRevision: AssetContentRevision,
        compatibility: EmbeddingCompatibility,
        generation: IndexGeneration
    ) {
        self.assetID = assetID
        self.pointID = pointID
        self.contentRevision = contentRevision
        self.compatibility = compatibility
        self.generation = generation
    }
}

/// Persisted preferences and workflow position.
public struct WorkflowState: Equatable, Sendable {
    public var scope: DateRange
    public var threshold: SimilarityThreshold
    public var pause: PauseState
    public var gate: InitialPassGate
    public var discoveryRevision: DiscoveryRevision
    public var indexGeneration: IndexGeneration
    /// Compatibility of vectors in `indexGeneration`; nil until the first vector is written.
    public var indexCompatibility: EmbeddingCompatibility?
    /// Last pass announced with a readiness notification, so each pass is announced once.
    public var notifiedPassID: VectorizationPassID?

    public init(
        scope: DateRange,
        threshold: SimilarityThreshold,
        pause: PauseState,
        gate: InitialPassGate,
        discoveryRevision: DiscoveryRevision,
        indexGeneration: IndexGeneration,
        indexCompatibility: EmbeddingCompatibility? = nil,
        notifiedPassID: VectorizationPassID? = nil
    ) {
        self.scope = scope
        self.threshold = threshold
        self.pause = pause
        self.gate = gate
        self.discoveryRevision = discoveryRevision
        self.indexGeneration = indexGeneration
        self.indexCompatibility = indexCompatibility
        self.notifiedPassID = notifiedPassID
    }

    /// State after a local-data reset: preferences kept, everything else restarted
    /// with new revision and generation numbers so stale work cannot be mistaken for current.
    public func afterReset() -> WorkflowState {
        WorkflowState(
            scope: scope,
            threshold: threshold,
            pause: .none,
            gate: InitialPassGate(),
            discoveryRevision: discoveryRevision.next(),
            indexGeneration: indexGeneration.next(),
            indexCompatibility: nil
        )
    }
}

/// Durable lazy-discovery position for one discovery revision.
public struct DiscoveryProgress: Equatable, Sendable {
    public let revision: DiscoveryRevision
    /// Last seed fully processed, in ascending `AssetID` order.
    public var seedCursor: AssetID?
    public var isSeedCursorExhausted: Bool
    /// Component expansion in progress, if any.
    public var expansion: ComponentExpansion.Snapshot?

    public init(
        revision: DiscoveryRevision,
        seedCursor: AssetID? = nil,
        isSeedCursorExhausted: Bool = false,
        expansion: ComponentExpansion.Snapshot? = nil
    ) {
        self.revision = revision
        self.seedCursor = seedCursor
        self.isSeedCursorExhausted = isSeedCursorExhausted
        self.expansion = expansion
    }
}

public enum JournalEntryKind: Equatable, Sendable {
    case vectorWrite([VectorWriteIntent])
    case deletion(group: GroupID, revision: MembershipRevision, assets: [AssetID], estimatedBytes: Int64?)
    case reset
}

public enum JournalPhase: Equatable, Sendable {
    /// Intent recorded; the external write may or may not have happened.
    case intended
    /// The external system confirmed the operation; local cleanup is still pending.
    case externalConfirmed
}

public struct JournalEntry: Equatable, Sendable {
    public let id: OperationID
    public let kind: JournalEntryKind
    public let phase: JournalPhase

    public init(id: OperationID, kind: JournalEntryKind, phase: JournalPhase) {
        self.id = id
        self.kind = kind
        self.phase = phase
    }
}

public struct LibraryStatistics: Equatable, Sendable {
    public let vectorizedPhotos: Int
    public let unavailablePhotos: Int
    public let reviewedGroups: Int
    public let deletedPhotos: Int
    /// Sum of known sizes only; an estimate, not reclaimed device storage.
    public let estimatedBytesFreed: Int64
    /// Deletions whose size was unknown and is therefore not included in the estimate.
    public let deletionsWithUnknownSize: Int

    public init(
        vectorizedPhotos: Int,
        unavailablePhotos: Int,
        reviewedGroups: Int,
        deletedPhotos: Int,
        estimatedBytesFreed: Int64,
        deletionsWithUnknownSize: Int
    ) {
        self.vectorizedPhotos = vectorizedPhotos
        self.unavailablePhotos = unavailablePhotos
        self.reviewedGroups = reviewedGroups
        self.deletedPhotos = deletedPhotos
        self.estimatedBytesFreed = estimatedBytesFreed
        self.deletionsWithUnknownSize = deletionsWithUnknownSize
    }
}
