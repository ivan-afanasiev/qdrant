import Foundation
import SwiftData

@ModelActor
actor SwiftDataScanStore: ScanSessionStoring {
    private let leaseDuration: TimeInterval = 120

    func createSession(rangeStart: Date, rangeEnd: Date, totalPhotos: Int) throws -> UUID {
        let session = ScanSessionEntity(
            rangeStart: rangeStart,
            rangeEnd: rangeEnd,
            totalPhotos: totalPhotos
        )
        modelContext.insert(session)
        try modelContext.save()
        return session.id
    }

    func loadSession(id: UUID) throws -> ScanSessionDTO? {
        try fetchSession(id)?.toDTO()
    }

    func updateSessionStatus(_ sessionId: UUID, status: ScanSessionStatus, indexedPhotos: Int?) throws {
        guard let session = try fetchSession(sessionId) else { return }
        session.status = status.rawValue
        if let count = indexedPhotos {
            session.indexedPhotos = count
        } else {
            updateSessionCounters(session)
        }
        if status != .scanning {
            session.leaseOwner = nil
            session.leaseExpiresAt = nil
        }
        try modelContext.save()
    }

    func latestCompletedSession() throws -> ScanSessionDTO? {
        let completedStatus = ScanSessionStatus.completed.rawValue
        let predicate = #Predicate<ScanSessionEntity> { $0.status == completedStatus }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.sortBy = [SortDescriptor(\.scannedAt, order: .reverse)]
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first?.toDTO()
    }

    func latestInterruptedSession() throws -> ScanSessionDTO? {
        var descriptor = FetchDescriptor<ScanSessionEntity>()
        descriptor.sortBy = [SortDescriptor(\.scannedAt, order: .reverse)]
        let sessions = try modelContext.fetch(descriptor)
        let now = Date()
        return sessions.first { session in
            let status = ScanSessionStatus(rawValue: session.status) ?? .scanning
            switch status {
            case .interrupted:
                return true
            case .scanning:
                return session.leaseExpiresAt == nil || session.leaseExpiresAt ?? .distantPast < now
            case .completed, .failed:
                return false
            }
        }?.toDTO()
    }

    func interruptActiveSessions() throws {
        let scanningStatus = ScanSessionStatus.scanning.rawValue
        let predicate = #Predicate<ScanSessionEntity> { $0.status == scanningStatus }
        let sessions = try modelContext.fetch(FetchDescriptor(predicate: predicate))
        for session in sessions {
            session.status = ScanSessionStatus.interrupted.rawValue
            session.leaseOwner = nil
            session.leaseExpiresAt = nil
        }
        if !sessions.isEmpty {
            try modelContext.save()
        }
    }

    func claimSessionLease(sessionId: UUID, owner: String, until: Date) throws -> Bool {
        guard let session = try fetchSession(sessionId) else { return false }
        let now = Date()
        if let existingOwner = session.leaseOwner,
           existingOwner != owner,
           let expiresAt = session.leaseExpiresAt,
           expiresAt > now {
            return false
        }
        session.leaseOwner = owner
        session.leaseExpiresAt = until
        session.status = ScanSessionStatus.scanning.rawValue
        try modelContext.save()
        return true
    }

    func persistScanBatch(
        sessionId: UUID,
        photos: [ScanPhotoRecord],
        similarityEdges: [SimilarityEdgeRecord]
    ) throws -> PersistScanBatchResult {
        guard let session = try fetchSession(sessionId) else {
            return PersistScanBatchResult(groups: [])
        }

        for record in photos {
            try upsertPhotoRecord(record, session: session)
        }

        var didChangeEdges = false
        for edge in similarityEdges {
            didChangeEdges = try upsertSimilarityEdge(edge, session: session) || didChangeEdges
        }

        updateSessionCounters(session)
        try modelContext.save()

        let groups = didChangeEdges
            ? try rebuildPendingGroups(sessionId: sessionId)
            : []

        return PersistScanBatchResult(groups: groups)
    }

    func loadPendingGroups() throws -> [DuplicateGroupDTO] {
        let pendingStatus = DuplicateGroupStatus.pending.rawValue
        let predicate = #Predicate<DuplicateGroupEntity> { $0.status == pendingStatus }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.sortBy = [SortDescriptor(\.detectedAt, order: .forward)]
        return try modelContext.fetch(descriptor).map { $0.toDTO() }
    }

    func loadPendingGroupsPage(offset: Int, limit: Int) throws -> [DuplicateGroupDTO] {
        let pendingStatus = DuplicateGroupStatus.pending.rawValue
        let predicate = #Predicate<DuplicateGroupEntity> { $0.status == pendingStatus }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.sortBy = [SortDescriptor(\.detectedAt, order: .forward)]
        descriptor.fetchOffset = offset
        descriptor.fetchLimit = limit
        return try modelContext.fetch(descriptor).map { $0.toDTO() }
    }

    func loadPendingGroup(id: UUID) throws -> DuplicateGroupDTO? {
        let predicate = #Predicate<DuplicateGroupEntity> { $0.id == id }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first?.toDTO()
    }

    func loadNextPendingGroup() throws -> DuplicateGroupDTO? {
        let pendingStatus = DuplicateGroupStatus.pending.rawValue
        let predicate = #Predicate<DuplicateGroupEntity> { $0.status == pendingStatus }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.sortBy = [SortDescriptor(\.detectedAt, order: .forward)]
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first?.toDTO()
    }

    func pendingGroupCount() throws -> Int {
        let pendingStatus = DuplicateGroupStatus.pending.rawValue
        let predicate = #Predicate<DuplicateGroupEntity> { $0.status == pendingStatus }
        var descriptor = FetchDescriptor<DuplicateGroupEntity>(predicate: predicate)
        descriptor.propertiesToFetch = []
        return try modelContext.fetchCount(descriptor)
    }

    func markGroupReviewed(groupId: UUID, keptVectorUUIDs: Set<String>) throws {
        guard let entity = try fetchGroup(groupId) else { return }
        entity.status = DuplicateGroupStatus.reviewed.rawValue
        entity.lastError = nil
        for member in entity.members {
            member.isKept = keptVectorUUIDs.contains(member.vectorUUID)
        }
        try modelContext.save()
    }

    func markGroupDeletionPending(groupId: UUID, keptVectorUUIDs: Set<String>, deletedVectorUUIDs: Set<String>) throws {
        guard let entity = try fetchGroup(groupId) else { return }
        entity.status = DuplicateGroupStatus.deleting.rawValue
        entity.lastError = nil
        for member in entity.members {
            if keptVectorUUIDs.contains(member.vectorUUID) {
                member.isKept = true
            } else if deletedVectorUUIDs.contains(member.vectorUUID) {
                member.isKept = false
            }
        }
        try modelContext.save()
    }

    func markGroupDeletionFailed(groupId: UUID, reason: String, deletedVectorUUIDs: Set<String>) throws {
        guard let entity = try fetchGroup(groupId) else { return }
        entity.status = DuplicateGroupStatus.pending.rawValue
        entity.lastError = reason
        try updatePhotoStatuses(vectorUUIDs: deletedVectorUUIDs, status: .pendingReindex, lastError: reason)
        try modelContext.save()
    }

    func markGroupDeleted(groupId: UUID, keptVectorUUIDs: Set<String>, deletedVectorUUIDs: Set<String>) throws {
        guard let entity = try fetchGroup(groupId) else { return }
        entity.status = DuplicateGroupStatus.deleted.rawValue
        entity.lastError = nil
        for member in entity.members {
            if keptVectorUUIDs.contains(member.vectorUUID) {
                member.isKept = true
            } else if deletedVectorUUIDs.contains(member.vectorUUID) {
                member.isKept = false
            }
        }
        try updatePhotoStatuses(vectorUUIDs: deletedVectorUUIDs, status: .deleted, lastError: nil)
        try modelContext.save()
    }

    func recoverPendingOperations() throws {
        let deletingStatus = DuplicateGroupStatus.deleting.rawValue
        let predicate = #Predicate<DuplicateGroupEntity> { $0.status == deletingStatus }
        let groups = try modelContext.fetch(FetchDescriptor(predicate: predicate))
        guard !groups.isEmpty else { return }

        for group in groups {
            group.status = DuplicateGroupStatus.pending.rawValue
            group.lastError = group.lastError ?? "Recovered unfinished deletion"
            let toReindex = Set(group.members.compactMap { member in
                member.isKept == false ? member.vectorUUID : nil
            })
            try updatePhotoStatuses(
                vectorUUIDs: toReindex,
                status: .pendingReindex,
                lastError: group.lastError
            )
        }
        try modelContext.save()
    }

    func resetAllData() throws {
        try deleteAll(ScanSessionEntity.self)
        try deleteAll(PhotoPointEntity.self)
        try deleteAll(DuplicateGroupEntity.self)
        try deleteAll(GroupMemberEntity.self)
        try deleteAll(SimilarityEdgeEntity.self)
        try modelContext.save()
    }

    nonisolated func countNewPhotosSince(date: Date, in dateRange: DateRange, using photoLibrary: any PhotoLibraryProviding) async throws -> Int {
        let newRange = DateRange(start: date, end: dateRange.end)
        return try await photoLibrary.countAssets(in: newRange)
    }

    func totalPhotosIndexed() throws -> Int {
        let indexedStatuses = [PhotoPointStatus.indexed.rawValue, PhotoPointStatus.skipped.rawValue]
        let predicate = #Predicate<PhotoPointEntity> { indexedStatuses.contains($0.status) }
        return try modelContext.fetchCount(FetchDescriptor(predicate: predicate))
    }

    func totalDuplicateGroupsFound() throws -> Int {
        let descriptor = FetchDescriptor<DuplicateGroupEntity>()
        return try modelContext.fetchCount(descriptor)
    }

    func totalPhotosDeleted() throws -> Int {
        let deletedStatus = PhotoPointStatus.deleted.rawValue
        let predicate = #Predicate<PhotoPointEntity> { $0.status == deletedStatus }
        return try modelContext.fetchCount(FetchDescriptor(predicate: predicate))
    }

    private func fetchSession(_ sessionId: UUID) throws -> ScanSessionEntity? {
        let predicate = #Predicate<ScanSessionEntity> { $0.id == sessionId }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func fetchGroup(_ groupId: UUID) throws -> DuplicateGroupEntity? {
        let predicate = #Predicate<DuplicateGroupEntity> { $0.id == groupId }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func upsertPhotoRecord(_ record: ScanPhotoRecord, session: ScanSessionEntity) throws {
        let assetLocalId = record.assetLocalId
        let predicate = #Predicate<PhotoPointEntity> { $0.assetLocalId == assetLocalId }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.fetchLimit = 1
        let entity = try modelContext.fetch(descriptor).first ?? {
            let point = PhotoPointEntity(
                assetLocalId: record.assetLocalId,
                vectorUUID: record.vectorUUID,
                embeddingDimensions: record.embeddingDimensions,
                status: record.status.rawValue,
                lastError: record.lastError,
                pixelWidth: record.pixelWidth,
                pixelHeight: record.pixelHeight,
                creationDate: record.creationDate,
                session: session
            )
            modelContext.insert(point)
            return point
        }()

        entity.vectorUUID = record.vectorUUID
        entity.embeddingDimensions = record.embeddingDimensions
        entity.indexedAt = .now
        entity.status = record.status.rawValue
        entity.lastError = record.lastError
        entity.pixelWidth = record.pixelWidth
        entity.pixelHeight = record.pixelHeight
        entity.creationDate = record.creationDate
        entity.session = session
    }

    private func upsertSimilarityEdge(_ edge: SimilarityEdgeRecord, session: ScanSessionEntity) throws -> Bool {
        let pairKey = edge.pairKey(sessionId: session.id)
        let predicate = #Predicate<SimilarityEdgeEntity> { $0.pairKey == pairKey }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.fetchLimit = 1

        if let existing = try modelContext.fetch(descriptor).first {
            if edge.score > existing.score {
                existing.score = edge.score
            }
            return false
        }

        let entity = SimilarityEdgeEntity(
            pairKey: pairKey,
            sourceVectorUUID: edge.normalizedSource,
            targetVectorUUID: edge.normalizedTarget,
            score: edge.score,
            session: session
        )
        modelContext.insert(entity)
        return true
    }

    private func rebuildPendingGroups(sessionId: UUID) throws -> [DuplicateGroup] {
        let edgePredicate = #Predicate<SimilarityEdgeEntity> { $0.session?.id == sessionId }
        let edges = try modelContext.fetch(FetchDescriptor(predicate: edgePredicate))
        guard !edges.isEmpty else {
            try deletePendingGroups(sessionId: sessionId)
            return []
        }

        var unionFind = UnionFind<String>()
        var allScores: [String: Float] = [:]

        for edge in edges {
            _ = unionFind.find(edge.sourceVectorUUID)
            _ = unionFind.find(edge.targetVectorUUID)
            unionFind.union(edge.sourceVectorUUID, edge.targetVectorUUID)
            allScores[edge.sourceVectorUUID] = max(allScores[edge.sourceVectorUUID, default: 0], edge.score)
            allScores[edge.targetVectorUUID] = max(allScores[edge.targetVectorUUID, default: 0], edge.score)
        }

        let activeStatuses = [PhotoPointStatus.indexed.rawValue, PhotoPointStatus.skipped.rawValue]
        let pointsPredicate = #Predicate<PhotoPointEntity> {
            $0.session?.id == sessionId && activeStatuses.contains($0.status)
        }
        let photoPoints = try modelContext.fetch(FetchDescriptor(predicate: pointsPredicate))
        let pointsByUUID = Dictionary(
            photoPoints.map { ($0.vectorUUID, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        let projected = unionFind.components().compactMap { component -> ProjectedGroup? in
            let sortedIds = component.sorted()
            let photos: [PhotoReference] = sortedIds.compactMap { uuid in
                guard let point = pointsByUUID[uuid] else { return nil }
                return PhotoReference(
                    id: uuid,
                    assetId: point.assetLocalId,
                    creationDate: point.creationDate,
                    pixelWidth: point.pixelWidth,
                    pixelHeight: point.pixelHeight,
                    score: allScores[uuid, default: 0]
                )
            }
            guard photos.count > 1 else { return nil }
            let best = photos.max(by: { $0.megapixels < $1.megapixels }) ?? photos[0]
            return ProjectedGroup(
                componentKey: sortedIds.joined(separator: "|"),
                duplicateGroup: DuplicateGroup(
                    id: UUID().uuidString,
                    photos: photos.sorted(by: { $0.megapixels > $1.megapixels }),
                    bestCandidate: best
                )
            )
        }

        guard let session = try fetchSession(sessionId) else { return [] }

        let pendingStatus = DuplicateGroupStatus.pending.rawValue
        let existingPredicate = #Predicate<DuplicateGroupEntity> {
            $0.session?.id == sessionId && $0.status == pendingStatus
        }
        let existingGroups = try modelContext.fetch(FetchDescriptor(predicate: existingPredicate))
        var existingByKey = Dictionary(
            uniqueKeysWithValues: existingGroups.map { ($0.componentKey, $0) }
        )

        let projectedKeys = Set(projected.map(\.componentKey))
        for group in existingGroups where !projectedKeys.contains(group.componentKey) {
            modelContext.delete(group)
        }

        for group in projected {
            let entity = existingByKey.removeValue(forKey: group.componentKey)
                ?? DuplicateGroupEntity(
                    status: DuplicateGroupStatus.pending.rawValue,
                    detectedAt: .now,
                    componentKey: group.componentKey,
                    lastError: nil,
                    session: session
                )

            if entity.modelContext == nil {
                modelContext.insert(entity)
            }

            entity.status = DuplicateGroupStatus.pending.rawValue
            entity.detectedAt = .now
            entity.componentKey = group.componentKey
            entity.lastError = nil
            for member in entity.members {
                modelContext.delete(member)
            }
            entity.members.removeAll()

            for photo in group.duplicateGroup.photos {
                let member = GroupMemberEntity(
                    assetLocalId: photo.assetId,
                    vectorUUID: photo.id,
                    score: photo.score,
                    pixelWidth: photo.pixelWidth,
                    pixelHeight: photo.pixelHeight,
                    creationDate: photo.creationDate,
                    group: entity
                )
                modelContext.insert(member)
            }
        }

        try modelContext.save()
        return projected.map(\.duplicateGroup).sorted(by: { $0.count > $1.count })
    }

    private func deletePendingGroups(sessionId: UUID) throws {
        let pendingStatus = DuplicateGroupStatus.pending.rawValue
        let predicate = #Predicate<DuplicateGroupEntity> {
            $0.session?.id == sessionId && $0.status == pendingStatus
        }
        let groups = try modelContext.fetch(FetchDescriptor(predicate: predicate))
        for group in groups {
            modelContext.delete(group)
        }
        if !groups.isEmpty {
            try modelContext.save()
        }
    }

    private func updateSessionCounters(_ session: ScanSessionEntity) {
        let points = session.photoPoints
        session.indexedPhotos = points.filter {
            let status = PhotoPointStatus(rawValue: $0.status) ?? .failed
            return status == .indexed
        }.count
        session.skippedPhotos = points.filter {
            let status = PhotoPointStatus(rawValue: $0.status) ?? .failed
            return status == .skipped
        }.count
        session.failedPhotos = points.filter {
            let status = PhotoPointStatus(rawValue: $0.status) ?? .failed
            return status == .failed || status == .pendingReindex
        }.count
        session.leaseExpiresAt = Date().addingTimeInterval(leaseDuration)
    }

    private func updatePhotoStatuses(
        vectorUUIDs: Set<String>,
        status: PhotoPointStatus,
        lastError: String?
    ) throws {
        guard !vectorUUIDs.isEmpty else { return }
        let predicate = #Predicate<PhotoPointEntity> { vectorUUIDs.contains($0.vectorUUID) }
        let points = try modelContext.fetch(FetchDescriptor(predicate: predicate))
        for point in points {
            point.status = status.rawValue
            point.lastError = lastError
        }
    }

    private func deleteAll<T: PersistentModel>(_ type: T.Type) throws {
        let items = try modelContext.fetch(FetchDescriptor<T>())
        for item in items {
            modelContext.delete(item)
        }
    }

    private struct ProjectedGroup {
        let componentKey: String
        let duplicateGroup: DuplicateGroup
    }
}
