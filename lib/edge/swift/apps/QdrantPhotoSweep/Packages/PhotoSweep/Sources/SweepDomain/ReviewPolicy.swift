import Foundation

/// Immutable snapshot of a group as opened on a card. External membership changes
/// produce a new revision; they never mutate an open snapshot or its selection.
public struct ReviewGroupSnapshot: Equatable, Sendable, Identifiable {
    public let id: GroupID
    public let revision: MembershipRevision
    public let discoveryRevision: DiscoveryRevision
    public let members: [AssetID]

    public init(id: GroupID, revision: MembershipRevision, discoveryRevision: DiscoveryRevision, members: [AssetID]) {
        self.id = id
        self.revision = revision
        self.discoveryRevision = discoveryRevision
        self.members = members
    }
}

/// What the user asked for on a card.
public enum ReviewCommitIntent: Equatable, Sendable {
    /// Keep the selected photos and delete the others. Selecting every photo keeps all.
    case keep(Set<AssetID>)
    /// Explicitly delete every photo in the group.
    case deleteAll
}

/// Validated decision ready for commit.
public enum ReviewDecision: Equatable, Sendable {
    /// Completes the review without deleting anything.
    case keepAll
    case delete(keep: Set<AssetID>, delete: Set<AssetID>)
}

public enum ReviewError: Error, Equatable, Sendable {
    /// An empty keep selection never deletes by itself; use explicit delete-all.
    case emptySelection
    case selectionOutsideGroup(Set<AssetID>)
    /// The group changed or disappeared since the card opened; refresh instead of committing.
    case conflict(GroupID)
}

/// Result of committing a decision through the deletion workflow.
public enum ReviewCommitOutcome: Equatable, Sendable {
    case completed
    case conflict
    /// The user rejected the Photos deletion prompt: keep the card, count nothing.
    case deletionDeclined
    case failed(String)
}

public enum SkipOutcome: Equatable, Sendable {
    /// Deferral was persisted; the card may advance.
    case persisted
    /// Persisting failed; the card must stay.
    case failed(String)
}

public enum KeepSelectionPolicy {
    /// Validates an intent against the open snapshot. Favorites get no special treatment.
    public static func validate(_ intent: ReviewCommitIntent, for group: ReviewGroupSnapshot) throws(ReviewError) -> ReviewDecision {
        let members = Set(group.members)
        switch intent {
        case .deleteAll:
            return .delete(keep: [], delete: members)
        case .keep(let keep):
            let outside = keep.subtracting(members)
            guard outside.isEmpty else { throw .selectionOutsideGroup(outside) }
            guard !keep.isEmpty else { throw .emptySelection }
            let delete = members.subtracting(keep)
            return delete.isEmpty ? .keepAll : .delete(keep: keep, delete: delete)
        }
    }
}

public enum ReviewCommitPolicy {
    /// Checks the snapshot against the current group before committing.
    /// - Parameters:
    ///   - currentRevision: nil when the group no longer exists.
    ///   - unavailable: assets that are inaccessible now (not necessarily deleted).
    public static func validateCurrent(
        _ snapshot: ReviewGroupSnapshot,
        currentRevision: MembershipRevision?,
        unavailable: Set<AssetID>
    ) throws(ReviewError) {
        guard let currentRevision, currentRevision == snapshot.revision,
              unavailable.isDisjoint(with: snapshot.members) else {
            throw .conflict(snapshot.id)
        }
    }
}
