import Foundation

/// Asset identity, content revision and vectorization outcome.
public protocol AssetRepository: Sendable {
    /// Registers or refreshes assets. New assets receive a fresh point ID; a changed
    /// content revision returns an asset to pending so it is vectorized again.
    func register(_ assets: [DiscoveredAsset]) async throws(PersistenceError) -> [AssetRecord]
    func assets(_ ids: [AssetID]) async throws(PersistenceError) -> [AssetID: AssetRecord]
    /// Removes assets confirmed deleted from the library. Never call this for assets
    /// that are merely inaccessible.
    func removeAssets(_ ids: [AssetID]) async throws(PersistenceError)
}

/// Journal around vector store writes. The vector store and metadata cannot share a
/// transaction, so intent is recorded first and closed only together with the metadata commit.
public protocol VectorWriteJournaling: Sendable {
    func beginVectorWrite(_ operation: OperationID, intents: [VectorWriteIntent]) async throws(PersistenceError)
    /// In one save: marks the assets vectorized, records pass outcomes and closes the entry.
    func commitVectorWrite(_ operation: OperationID, pass: VectorizationPassID?) async throws(PersistenceError)
    /// In one save: returns the intended assets to pending and closes the entry.
    /// Call after removing any points that may have been written.
    func abandonVectorWrite(_ operation: OperationID) async throws(PersistenceError)
}

/// Checkpointed vectorization passes. At most one pass is active.
public protocol VectorizationPassRepository: Sendable {
    /// Persists a new active pass and its work set, superseding any unfinished pass.
    func beginPass(_ pass: VectorizationPass) async throws(PersistenceError)
    func activePass() async throws(PersistenceError) -> VectorizationPass?
    /// In one save: marks assets deferred and records the pass outcomes.
    func recordDeferred(_ deferrals: [AssetID: DeferralReason], pass: VectorizationPassID) async throws(PersistenceError)
    func finishPass(_ id: VectorizationPassID) async throws(PersistenceError)
}

public protocol WorkflowStateRepository: Sendable {
    /// Nil before the first save.
    func loadWorkflowState() async throws(PersistenceError) -> WorkflowState?
    func saveWorkflowState(_ state: WorkflowState) async throws(PersistenceError)
}

public protocol DiscoveryProgressRepository: Sendable {
    func discoveryProgress(for revision: DiscoveryRevision) async throws(PersistenceError) -> DiscoveryProgress?
    func saveDiscoveryProgress(_ progress: DiscoveryProgress) async throws(PersistenceError)
}

/// Groups, memberships, review order, decisions and suppression.
public protocol ReviewRepository: Sendable {
    /// In one save: stores the group and membership, appends it to the fresh review order
    /// and stores the discovery progress that produced it.
    func publishGroup(_ group: ReviewGroupSnapshot, derivedFrom: [GroupID], progress: DiscoveryProgress) async throws(PersistenceError)
    /// Current snapshot of a group that is not retired.
    func group(_ id: GroupID) async throws(PersistenceError) -> ReviewGroupSnapshot?
    /// Groups this group was derived from (merge/split lineage).
    func lineage(of id: GroupID) async throws(PersistenceError) -> [GroupID]
    func reviewQueue(for revision: DiscoveryRevision) async throws(PersistenceError) -> ReviewQueue
    /// Replaces the membership and increments the membership revision.
    func updateMembership(of id: GroupID, members: [AssetID]) async throws(PersistenceError) -> ReviewGroupSnapshot
    /// Durable Skip: moves the group to the end of the deferred order.
    func deferGroup(_ id: GroupID) async throws(PersistenceError)
    /// In one save: completes the group, freezes its reviewed membership for suppression
    /// and records the reviewed-group statistic exactly once per operation.
    func completeGroup(_ id: GroupID, operation: OperationID) async throws(PersistenceError)
    /// True when any asset belongs to a group completed in this discovery revision.
    func isSuppressed(_ assets: Set<AssetID>, revision: DiscoveryRevision) async throws(PersistenceError) -> Bool
    /// Threshold change or rescan: groups from older revisions leave the queue,
    /// and their deferrals and suppression no longer apply.
    func retireGroups(before revision: DiscoveryRevision) async throws(PersistenceError)
}

/// Recoverable external operations other than the vector-write helpers above.
public protocol OperationJournal: Sendable {
    /// Open entries in creation order.
    func openJournalEntries() async throws(PersistenceError) -> [JournalEntry]
    func beginDeletion(
        _ operation: OperationID,
        group: GroupID,
        revision: MembershipRevision,
        assets: [AssetID],
        estimatedBytes: Int64?
    ) async throws(PersistenceError)
    func confirmExternalDeletion(_ operation: OperationID) async throws(PersistenceError)
    func closeJournalEntry(_ operation: OperationID) async throws(PersistenceError)
}

public protocol StatisticsRepository: Sendable {
    /// Records confirmed deleted photos once per operation. Returns false if already recorded.
    @discardableResult
    func recordDeletion(
        _ operation: OperationID,
        photoCount: Int,
        estimatedBytes: Int64?,
        revision: DiscoveryRevision
    ) async throws(PersistenceError) -> Bool
    func statistics() async throws(PersistenceError) -> LibraryStatistics
}

/// Restartable local-data reset.
public protocol LocalDataResetting: Sendable {
    func beginReset(_ operation: OperationID) async throws(PersistenceError)
    /// Deletes all metadata except open deletion entries (still needed for recovery),
    /// statistics events and the reset entry itself, then stores `workflow`
    /// (nil removes any stored workflow state).
    func clearMetadataForReset(keeping workflow: WorkflowState?) async throws(PersistenceError)
    func finishReset(_ operation: OperationID) async throws(PersistenceError)
}
