import Foundation
import SwiftData
import SweepDomain

// MARK: - WorkflowStateRepository

extension SwiftDataMetadataStore: WorkflowStateRepository {
    static let workflowKey = "workflow"

    public func loadWorkflowState() async throws(PersistenceError) -> WorkflowState? {
        try perform { try currentWorkflowState() }
    }

    @discardableResult
    public func modifyWorkflowState(_ change: @Sendable (inout WorkflowState) -> Void) async throws(PersistenceError) -> WorkflowState? {
        try perform {
            guard var state = try currentWorkflowState() else { return nil }
            change(&state)
            try applyWorkflowState(state)
            try save()
            return state
        }
    }

    func currentWorkflowState() throws -> WorkflowState? {
        guard let entity = try workflowEntity() else { return nil }
        guard let threshold = SimilarityThreshold(entity.threshold) else {
            throw PersistenceError.invalidState("Stored threshold \(entity.threshold) is invalid")
        }
        let gate: InitialPassGate.State = entity.gateIsOpen
            ? .open(deferredCount: entity.gateDeferredCount)
            : .awaitingInitialPass(entity.gatePassID.map(VectorizationPassID.init))
        return WorkflowState(
            scope: DateRange(start: entity.scopeStart, end: entity.scopeEnd),
            threshold: threshold,
            pause: PauseState(isPausedByUser: entity.isPausedByUser),
            gate: InitialPassGate(state: gate),
            discoveryRevision: DiscoveryRevision(entity.discoveryRevision),
            indexGeneration: IndexGeneration(entity.indexGeneration),
            indexCompatibility: Self.indexCompatibility(of: entity)
        )
    }

    public func saveWorkflowState(_ state: WorkflowState) async throws(PersistenceError) {
        try perform {
            try applyWorkflowState(state)
            try save()
        }
    }

    static func indexCompatibility(of entity: WorkflowStateEntity) -> EmbeddingCompatibility? {
        guard let model = entity.indexModel, let revision = entity.indexModelRevision,
              let preprocessing = entity.indexPreprocessing, let dimensions = entity.indexDimensions else { return nil }
        return EmbeddingCompatibility(model: model, modelRevision: revision, preprocessing: preprocessing, dimensions: dimensions)
    }

    func workflowEntity() throws -> WorkflowStateEntity? {
        let key = Self.workflowKey
        return try modelContext.fetch(FetchDescriptor<WorkflowStateEntity>(predicate: #Predicate { $0.key == key })).first
    }

    func applyWorkflowState(_ state: WorkflowState) throws {
        let entity: WorkflowStateEntity
        if let existing = try workflowEntity() {
            entity = existing
        } else {
            entity = WorkflowStateEntity(key: Self.workflowKey)
            modelContext.insert(entity)
        }
        entity.scopeStart = state.scope.start
        entity.scopeEnd = state.scope.end
        entity.threshold = state.threshold.value
        entity.isPausedByUser = state.pause.isPausedByUser
        entity.discoveryRevision = state.discoveryRevision.rawValue
        entity.indexGeneration = state.indexGeneration.rawValue
        entity.indexModel = state.indexCompatibility?.model
        entity.indexModelRevision = state.indexCompatibility?.modelRevision
        entity.indexPreprocessing = state.indexCompatibility?.preprocessing
        entity.indexDimensions = state.indexCompatibility?.dimensions
        switch state.gate.state {
        case .awaitingInitialPass(let pass):
            entity.gateIsOpen = false
            entity.gatePassID = pass?.rawValue
            entity.gateDeferredCount = 0
        case .open(let deferredCount):
            entity.gateIsOpen = true
            entity.gatePassID = nil
            entity.gateDeferredCount = deferredCount
        }
    }
}

// MARK: - DiscoveryProgressRepository

extension SwiftDataMetadataStore: DiscoveryProgressRepository {
    public func discoveryProgress(for revision: DiscoveryRevision) async throws(PersistenceError) -> DiscoveryProgress? {
        try perform {
            let value = revision.rawValue
            guard let entity = try modelContext.fetch(FetchDescriptor<DiscoveryProgressEntity>(
                predicate: #Predicate { $0.revision == value }
            )).first else { return nil }
            return DiscoveryProgress(
                revision: revision,
                seedCursor: entity.seedCursor.map(AssetID.init),
                isSeedCursorExhausted: entity.isSeedCursorExhausted,
                expansion: try expansionSnapshot(entity)
            )
        }
    }

    public func saveDiscoveryProgress(_ progress: DiscoveryProgress) async throws(PersistenceError) {
        try perform {
            try applyDiscoveryProgress(progress)
            try save()
        }
    }

    func expansionSnapshot(_ entity: DiscoveryProgressEntity) throws -> ComponentExpansion.Snapshot? {
        guard let seed = entity.expansionSeed, let start = entity.expansionScopeStart, let end = entity.expansionScopeEnd,
              let thresholdValue = entity.expansionThreshold, let generation = entity.expansionGeneration else { return nil }
        guard let threshold = SimilarityThreshold(thresholdValue) else {
            throw PersistenceError.invalidState("Stored expansion threshold \(thresholdValue) is invalid")
        }
        let revision = entity.revision
        let entries = try modelContext.fetch(FetchDescriptor<FrontierEntryEntity>(
            predicate: #Predicate { $0.revision == revision },
            sortBy: [SortDescriptor(\.order)]
        ))
        return ComponentExpansion.Snapshot(
            seed: AssetID(seed),
            scope: DateRange(start: start, end: end),
            threshold: threshold,
            generation: IndexGeneration(generation),
            visited: entries.map { AssetID($0.assetID) },
            queriedCount: entity.queriedCount
        )
    }

    /// Updates progress without saving. Frontier rows of the same expansion are appended,
    /// not rewritten, so checkpoints of large components stay proportional to new members.
    func applyDiscoveryProgress(_ progress: DiscoveryProgress) throws {
        let revision = progress.revision.rawValue
        let entity: DiscoveryProgressEntity
        if let existing = try modelContext.fetch(FetchDescriptor<DiscoveryProgressEntity>(
            predicate: #Predicate { $0.revision == revision }
        )).first {
            entity = existing
        } else {
            entity = DiscoveryProgressEntity(revision: revision)
            modelContext.insert(entity)
        }
        entity.seedCursor = progress.seedCursor?.rawValue
        entity.isSeedCursorExhausted = progress.isSeedCursorExhausted

        let stored = try modelContext.fetch(FetchDescriptor<FrontierEntryEntity>(
            predicate: #Predicate { $0.revision == revision },
            sortBy: [SortDescriptor(\.order)]
        ))
        guard let expansion = progress.expansion else {
            stored.forEach(modelContext.delete)
            entity.expansionSeed = nil
            entity.expansionScopeStart = nil
            entity.expansionScopeEnd = nil
            entity.expansionThreshold = nil
            entity.expansionGeneration = nil
            entity.queriedCount = 0
            return
        }
        let isSameExpansion = entity.expansionSeed == expansion.seed.rawValue
            && stored.count <= expansion.visited.count
            && zip(stored, expansion.visited).allSatisfy { $0.assetID == $1.rawValue }
        var firstNew = stored.count
        if !isSameExpansion {
            stored.forEach(modelContext.delete)
            firstNew = 0
        }
        for order in firstNew..<expansion.visited.count {
            modelContext.insert(FrontierEntryEntity(revision: revision, order: order, assetID: expansion.visited[order].rawValue))
        }
        entity.expansionSeed = expansion.seed.rawValue
        entity.expansionScopeStart = expansion.scope.start
        entity.expansionScopeEnd = expansion.scope.end
        entity.expansionThreshold = expansion.threshold.value
        entity.expansionGeneration = expansion.generation.rawValue
        entity.queriedCount = expansion.queriedCount
    }
}

// MARK: - ReviewRepository

extension SwiftDataMetadataStore: ReviewRepository {
    public func publishGroup(_ group: ReviewGroupSnapshot, derivedFrom: [GroupID], progress: DiscoveryProgress) async throws(PersistenceError) {
        try perform {
            guard try groupEntity(group.id) == nil else {
                throw PersistenceError.invalidState("Group \(group.id.rawValue) already exists")
            }
            var descriptor = FetchDescriptor<GroupEntity>(sortBy: [SortDescriptor(\.freshOrder, order: .reverse)])
            descriptor.fetchLimit = 1
            let nextOrder = (try modelContext.fetch(descriptor).first?.freshOrder ?? 0) + 1
            modelContext.insert(GroupEntity(
                groupID: group.id.rawValue,
                discoveryRevision: group.discoveryRevision.rawValue,
                membershipRevision: group.revision.rawValue,
                freshOrder: nextOrder,
                derivedFrom: derivedFrom.map(\.rawValue)
            ))
            insertMembers(group.members, of: group.id.rawValue)
            try applyDiscoveryProgress(progress)
            try save()
        }
    }

    public func group(_ id: GroupID) async throws(PersistenceError) -> ReviewGroupSnapshot? {
        try perform {
            guard let entity = try groupEntity(id), entity.state != "retired" else { return nil }
            return try snapshot(of: entity)
        }
    }

    public func lineage(of id: GroupID) async throws(PersistenceError) -> [GroupID] {
        try perform {
            try groupEntity(id)?.derivedFrom.map(GroupID.init) ?? []
        }
    }

    public func reviewQueue(for revision: DiscoveryRevision) async throws(PersistenceError) -> ReviewQueue {
        try perform {
            let value = revision.rawValue
            let groups = try modelContext.fetch(FetchDescriptor<GroupEntity>(predicate: #Predicate { $0.discoveryRevision == value }))
            let fresh = groups.filter { $0.state == "fresh" }.sorted { $0.freshOrder < $1.freshOrder }
            let deferred = groups.filter { $0.state == "deferred" }.sorted { ($0.deferredOrder ?? 0) < ($1.deferredOrder ?? 0) }
            return ReviewQueue(fresh: fresh.map { GroupID($0.groupID) }, deferred: deferred.map { GroupID($0.groupID) })
        }
    }

    public func updateMembership(of id: GroupID, members: [AssetID]) async throws(PersistenceError) -> ReviewGroupSnapshot {
        try perform {
            guard let entity = try groupEntity(id) else { throw PersistenceError.notFound("Group \(id.rawValue)") }
            guard entity.state == "fresh" || entity.state == "deferred" else {
                throw PersistenceError.invalidState("Group \(id.rawValue) is \(entity.state) and cannot change membership")
            }
            try replaceMembers(of: id.rawValue, with: members)
            entity.membershipRevision += 1
            try save()
            return ReviewGroupSnapshot(
                id: id,
                revision: MembershipRevision(entity.membershipRevision),
                discoveryRevision: DiscoveryRevision(entity.discoveryRevision),
                members: members
            )
        }
    }

    public func deferGroup(_ id: GroupID) async throws(PersistenceError) {
        try perform {
            guard let entity = try groupEntity(id) else { throw PersistenceError.notFound("Group \(id.rawValue)") }
            guard entity.state == "fresh" || entity.state == "deferred" else {
                throw PersistenceError.invalidState("Group \(id.rawValue) is \(entity.state) and cannot be skipped")
            }
            var descriptor = FetchDescriptor<GroupEntity>(sortBy: [SortDescriptor(\.deferredOrder, order: .reverse)])
            descriptor.fetchLimit = 1
            let lastOrder = try modelContext.fetch(descriptor).first?.deferredOrder ?? 0
            entity.state = "deferred"
            entity.deferredOrder = lastOrder + 1
            try save()
        }
    }

    public func completeGroup(_ id: GroupID, operation: OperationID) async throws(PersistenceError) {
        try perform {
            guard let entity = try groupEntity(id) else { throw PersistenceError.notFound("Group \(id.rawValue)") }
            if entity.state == "completed" {
                guard entity.completionOperation == operation.rawValue else {
                    throw PersistenceError.invalidState("Group \(id.rawValue) was completed by another operation")
                }
                return
            }
            guard entity.state == "fresh" || entity.state == "deferred" else {
                throw PersistenceError.invalidState("Group \(id.rawValue) is \(entity.state)")
            }
            entity.state = "completed"
            entity.deferredOrder = nil
            entity.completionOperation = operation.rawValue
            try insertStatisticsEvent(kind: "groupReviewed", operation: operation, photoCount: 0, estimatedBytes: nil, revision: entity.discoveryRevision)
            try save()
        }
    }

    public func isSuppressed(_ assets: Set<AssetID>, revision: DiscoveryRevision) async throws(PersistenceError) -> Bool {
        try perform {
            let value = revision.rawValue
            let completed = try modelContext.fetch(FetchDescriptor<GroupEntity>(
                predicate: #Predicate { $0.discoveryRevision == value && $0.state == "completed" }
            )).map(\.groupID)
            guard !completed.isEmpty else { return false }
            let assetIDs = assets.map(\.rawValue)
            let matches = try modelContext.fetchCount(FetchDescriptor<GroupMemberEntity>(
                predicate: #Predicate { completed.contains($0.groupID) && assetIDs.contains($0.assetID) }
            ))
            return matches > 0
        }
    }

    public func retireGroups(before revision: DiscoveryRevision) async throws(PersistenceError) {
        try perform {
            let value = revision.rawValue
            let old = try modelContext.fetch(FetchDescriptor<GroupEntity>(
                predicate: #Predicate { $0.discoveryRevision < value && $0.state != "retired" }
            ))
            for entity in old {
                entity.state = "retired"
                entity.deferredOrder = nil
            }
            try modelContext.fetch(FetchDescriptor<DiscoveryProgressEntity>(predicate: #Predicate { $0.revision < value }))
                .forEach(modelContext.delete)
            try modelContext.fetch(FetchDescriptor<FrontierEntryEntity>(predicate: #Predicate { $0.revision < value }))
                .forEach(modelContext.delete)
            try save()
        }
    }

    func groupEntity(_ id: GroupID) throws -> GroupEntity? {
        let value = id.rawValue
        return try modelContext.fetch(FetchDescriptor<GroupEntity>(predicate: #Predicate { $0.groupID == value })).first
    }

    func memberEntities(of group: UUID) throws -> [GroupMemberEntity] {
        try modelContext.fetch(FetchDescriptor<GroupMemberEntity>(
            predicate: #Predicate { $0.groupID == group },
            sortBy: [SortDescriptor(\.position)]
        ))
    }

    func insertMembers(_ members: [AssetID], of group: UUID) {
        for (position, member) in members.enumerated() {
            modelContext.insert(GroupMemberEntity(groupID: group, assetID: member.rawValue, position: position))
        }
    }

    func snapshot(of entity: GroupEntity) throws -> ReviewGroupSnapshot {
        ReviewGroupSnapshot(
            id: GroupID(entity.groupID),
            revision: MembershipRevision(entity.membershipRevision),
            discoveryRevision: DiscoveryRevision(entity.discoveryRevision),
            members: try memberEntities(of: entity.groupID).map { AssetID($0.assetID) }
        )
    }
}
