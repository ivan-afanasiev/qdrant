import Foundation
import SwiftData
import SweepDomain

// MARK: - DiscoveryRepository

extension SwiftDataMetadataStore: DiscoveryRepository {
    public func nextSeed(revision: DiscoveryRevision, scope: DateRange, generation: IndexGeneration) async throws(PersistenceError) -> AssetRecord? {
        try perform {
            let examined = revision.rawValue
            let generationValue: Int? = generation.rawValue
            let start = scope.start
            let end = scope.end
            var descriptor = FetchDescriptor<AssetEntity>(
                predicate: #Predicate {
                    $0.state == "vectorized" && $0.generation == generationValue && $0.isDated
                        && $0.seedDate >= start && $0.seedDate <= end && $0.examinedRevision != examined
                },
                sortBy: [SortDescriptor(\.seedDate, order: .reverse), SortDescriptor(\.assetID, order: .reverse)]
            )
            descriptor.fetchLimit = 1
            return try modelContext.fetch(descriptor).first.map(Self.record(from:))
        }
    }

    public func pendingGroups(containing assets: Set<AssetID>, revision: DiscoveryRevision) async throws(PersistenceError) -> [GroupID] {
        try perform {
            try pendingGroupEntities(containing: assets, revision: revision.rawValue).map { GroupID($0.groupID) }
        }
    }

    public func completeComponent(members: [AssetID], outcome: ComponentOutcome, progress: DiscoveryProgress) async throws(PersistenceError) {
        try perform {
            let revision = progress.revision.rawValue
            for entity in try fetchAssetEntities(members.map(\.rawValue)).values {
                entity.examinedRevision = revision
            }
            switch outcome {
            case .discarded:
                break
            case .published(let group, let derivedFrom):
                guard try groupEntity(group.id) == nil else {
                    throw PersistenceError.invalidState("Group \(group.id.rawValue) already exists")
                }
                for absorbed in derivedFrom {
                    guard let entity = try groupEntity(absorbed) else { continue }
                    entity.state = "retired"
                    entity.deferredOrder = nil
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
            case .merged(let id, let newMembers):
                guard let entity = try groupEntity(id), entity.state == "fresh" || entity.state == "deferred" else {
                    throw PersistenceError.invalidState("Group \(id.rawValue) cannot absorb new members")
                }
                try replaceMembers(of: id.rawValue, with: newMembers)
                entity.membershipRevision += 1
            }
            try applyDiscoveryProgress(progress)
            try save()
        }
    }

    func pendingGroupEntities(containing assets: Set<AssetID>, revision: Int) throws -> [GroupEntity] {
        let assetIDs = assets.map(\.rawValue)
        let memberships = try modelContext.fetch(FetchDescriptor<GroupMemberEntity>(predicate: #Predicate { assetIDs.contains($0.assetID) }))
        let groupIDs = Array(Set(memberships.map(\.groupID)))
        guard !groupIDs.isEmpty else { return [] }
        return try modelContext.fetch(FetchDescriptor<GroupEntity>(
            predicate: #Predicate { groupIDs.contains($0.groupID) && $0.discoveryRevision == revision },
            sortBy: [SortDescriptor(\.freshOrder)]
        )).filter { $0.state == "fresh" || $0.state == "deferred" }
    }

    /// Updates member rows in place; unique keys must not be deleted and re-inserted in one save.
    func replaceMembers(of group: UUID, with members: [AssetID]) throws {
        var existing = Dictionary(try memberEntities(of: group).map { ($0.assetID, $0) }, uniquingKeysWith: { first, _ in first })
        for (position, member) in members.enumerated() {
            if let row = existing.removeValue(forKey: member.rawValue) {
                row.position = position
            } else {
                modelContext.insert(GroupMemberEntity(groupID: group, assetID: member.rawValue, position: position))
            }
        }
        existing.values.forEach(modelContext.delete)
    }
}

// MARK: - DeletionRepository

extension SwiftDataMetadataStore: DeletionRepository {
    public func finishDeletion(_ operation: OperationID, deleted: [AssetID], estimatedBytes: Int64?, revision: DiscoveryRevision) async throws(PersistenceError) {
        try perform {
            guard let journal = try journalEntity(operation), journal.kind == "deletion" else {
                // Already finished: replaying cleanup is a no-op.
                return
            }
            for entity in try fetchAssetEntities(deleted.map(\.rawValue)).values {
                modelContext.delete(entity)
            }
            if let groupID = journal.groupID, let group = try groupEntity(GroupID(groupID)),
               group.state == "fresh" || group.state == "deferred" {
                group.state = "completed"
                group.deferredOrder = nil
                group.completionOperation = operation.rawValue
                try insertStatisticsEvent(kind: "groupReviewed", operation: operation, photoCount: 0, estimatedBytes: nil, revision: group.discoveryRevision)
            }
            if !deleted.isEmpty {
                try insertStatisticsEvent(
                    kind: "photosDeleted", operation: operation, photoCount: deleted.count,
                    estimatedBytes: estimatedBytes, revision: revision.rawValue
                )
            }
            modelContext.delete(journal)
            try save()
        }
    }
}
