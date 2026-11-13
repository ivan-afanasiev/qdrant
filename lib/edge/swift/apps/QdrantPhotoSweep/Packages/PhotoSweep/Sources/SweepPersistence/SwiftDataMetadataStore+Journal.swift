import Foundation
import SwiftData
import SweepDomain

// MARK: - OperationJournal

extension SwiftDataMetadataStore: OperationJournal {
    public func openJournalEntries() async throws(PersistenceError) -> [JournalEntry] {
        try perform {
            let entries = try modelContext.fetch(FetchDescriptor<JournalEntity>(sortBy: [SortDescriptor(\.sequence)]))
            return try entries.map { entity in
                JournalEntry(
                    id: OperationID(entity.operationID),
                    kind: try kind(of: entity),
                    phase: entity.phase == "externalConfirmed" ? .externalConfirmed : .intended
                )
            }
        }
    }

    public func beginDeletion(
        _ operation: OperationID,
        group: GroupID,
        revision: MembershipRevision,
        assets: [AssetID],
        estimatedBytes: Int64?
    ) async throws(PersistenceError) {
        try perform {
            guard try journalEntity(operation) == nil else {
                throw PersistenceError.invalidState("Journal entry \(operation.rawValue) already exists")
            }
            let entity = JournalEntity(operationID: operation.rawValue, kind: "deletion", sequence: try nextJournalSequence())
            entity.groupID = group.rawValue
            entity.membershipRevision = revision.rawValue
            entity.assetIDs = assets.map(\.rawValue)
            entity.estimatedBytes = estimatedBytes
            modelContext.insert(entity)
            try save()
        }
    }

    public func confirmExternalDeletion(_ operation: OperationID) async throws(PersistenceError) {
        try perform {
            guard let entity = try journalEntity(operation), entity.kind == "deletion" else {
                throw PersistenceError.notFound("Deletion \(operation.rawValue)")
            }
            entity.phase = "externalConfirmed"
            try save()
        }
    }

    public func closeJournalEntry(_ operation: OperationID) async throws(PersistenceError) {
        try perform {
            guard let entity = try journalEntity(operation) else { return }
            try intents(of: operation.rawValue).forEach(modelContext.delete)
            modelContext.delete(entity)
            try save()
        }
    }

    func kind(of entity: JournalEntity) throws -> JournalEntryKind {
        switch entity.kind {
        case "vectorWrite":
            let intents = try intents(of: entity.operationID).map { row in
                VectorWriteIntent(
                    assetID: AssetID(row.assetID),
                    pointID: VectorPointID(row.pointID),
                    contentRevision: AssetContentRevision(row.contentRevision),
                    compatibility: EmbeddingCompatibility(
                        model: row.embeddingModel,
                        modelRevision: row.modelRevision,
                        preprocessing: row.preprocessing,
                        dimensions: row.dimensions
                    ),
                    generation: IndexGeneration(row.generation)
                )
            }
            return .vectorWrite(intents)
        case "deletion":
            guard let group = entity.groupID, let revision = entity.membershipRevision else {
                throw PersistenceError.invalidState("Deletion entry \(entity.operationID) is incomplete")
            }
            return .deletion(
                group: GroupID(group),
                revision: MembershipRevision(revision),
                assets: entity.assetIDs.map(AssetID.init),
                estimatedBytes: entity.estimatedBytes
            )
        case "reset":
            return .reset
        default:
            throw PersistenceError.invalidState("Unknown journal kind \(entity.kind)")
        }
    }
}

// MARK: - StatisticsRepository

extension SwiftDataMetadataStore: StatisticsRepository {
    @discardableResult
    public func recordDeletion(
        _ operation: OperationID,
        photoCount: Int,
        estimatedBytes: Int64?,
        revision: DiscoveryRevision
    ) async throws(PersistenceError) -> Bool {
        try perform {
            let inserted = try insertStatisticsEvent(
                kind: "photosDeleted", operation: operation, photoCount: photoCount,
                estimatedBytes: estimatedBytes, revision: revision.rawValue
            )
            try save()
            return inserted
        }
    }

    public func statistics() async throws(PersistenceError) -> LibraryStatistics {
        try perform {
            let vectorized = try modelContext.fetchCount(FetchDescriptor<AssetEntity>(predicate: #Predicate { $0.state == "vectorized" }))
            let deferred = try modelContext.fetchCount(FetchDescriptor<AssetEntity>(predicate: #Predicate { $0.state == "deferred" }))
            let reviewed = try modelContext.fetchCount(FetchDescriptor<StatisticsEventEntity>(predicate: #Predicate { $0.kind == "groupReviewed" }))
            let deletions = try modelContext.fetch(FetchDescriptor<StatisticsEventEntity>(predicate: #Predicate { $0.kind == "photosDeleted" }))
            return LibraryStatistics(
                vectorizedPhotos: vectorized,
                unavailablePhotos: deferred,
                reviewedGroups: reviewed,
                deletedPhotos: deletions.reduce(0) { $0 + $1.photoCount },
                estimatedBytesFreed: deletions.reduce(0) { $0 + ($1.estimatedBytes ?? 0) },
                deletionsWithUnknownSize: deletions.filter { $0.estimatedBytes == nil }.count
            )
        }
    }

    /// Inserts an event unless the same kind was already recorded for the operation.
    @discardableResult
    func insertStatisticsEvent(kind: String, operation: OperationID, photoCount: Int, estimatedBytes: Int64?, revision: Int) throws -> Bool {
        let key = "\(kind)|\(operation.rawValue.uuidString)"
        let existing = try modelContext.fetchCount(FetchDescriptor<StatisticsEventEntity>(predicate: #Predicate { $0.key == key }))
        guard existing == 0 else { return false }
        modelContext.insert(StatisticsEventEntity(
            kind: kind, operationID: operation.rawValue, photoCount: photoCount,
            estimatedBytes: estimatedBytes, discoveryRevision: revision
        ))
        return true
    }
}

// MARK: - LocalDataResetting

extension SwiftDataMetadataStore: LocalDataResetting {
    public func beginReset(_ operation: OperationID) async throws(PersistenceError) {
        try perform {
            if let existing = try journalEntity(operation) {
                guard existing.kind == "reset" else {
                    throw PersistenceError.invalidState("Journal entry \(operation.rawValue) is not a reset")
                }
                return
            }
            modelContext.insert(JournalEntity(operationID: operation.rawValue, kind: "reset", sequence: try nextJournalSequence()))
            try save()
        }
    }

    public func clearMetadataForReset(keeping workflow: WorkflowState?) async throws(PersistenceError) {
        try perform {
            try modelContext.fetch(FetchDescriptor<AssetEntity>()).forEach(modelContext.delete)
            try deleteAllPasses()
            try modelContext.fetch(FetchDescriptor<DiscoveryProgressEntity>()).forEach(modelContext.delete)
            try modelContext.fetch(FetchDescriptor<FrontierEntryEntity>()).forEach(modelContext.delete)
            try modelContext.fetch(FetchDescriptor<GroupEntity>()).forEach(modelContext.delete)
            try modelContext.fetch(FetchDescriptor<GroupMemberEntity>()).forEach(modelContext.delete)
            try modelContext.fetch(FetchDescriptor<JournalIntentEntity>()).forEach(modelContext.delete)
            // Deletion entries survive: an already-started Photos deletion must still reconcile.
            try modelContext.fetch(FetchDescriptor<JournalEntity>(predicate: #Predicate { $0.kind == "vectorWrite" }))
                .forEach(modelContext.delete)
            if let workflow {
                try applyWorkflowState(workflow)
            } else if let stored = try workflowEntity() {
                modelContext.delete(stored)
            }
            try save()
        }
    }

    public func finishReset(_ operation: OperationID) async throws(PersistenceError) {
        try perform {
            guard let entity = try journalEntity(operation), entity.kind == "reset" else { return }
            modelContext.delete(entity)
            try save()
        }
    }
}
