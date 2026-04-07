import Foundation
import SwiftData

@ModelActor
actor SwiftDataScanStore: ScanSessionStoring {

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

    func updateSessionStatus(_ sessionId: UUID, status: ScanSessionStatus, indexedPhotos: Int?) throws {
        let predicate = #Predicate<ScanSessionEntity> { $0.id == sessionId }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.fetchLimit = 1
        guard let session = try modelContext.fetch(descriptor).first else { return }
        session.status = status.rawValue
        if let count = indexedPhotos {
            session.indexedPhotos = count
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
        let interruptedStatus = ScanSessionStatus.interrupted.rawValue
        let predicate = #Predicate<ScanSessionEntity> { $0.status == interruptedStatus }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.sortBy = [SortDescriptor(\.scannedAt, order: .reverse)]
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first?.toDTO()
    }

    func interruptActiveSessions() throws {
        let scanningStatus = ScanSessionStatus.scanning.rawValue
        let predicate = #Predicate<ScanSessionEntity> {
            $0.status == scanningStatus
        }
        let sessions = try modelContext.fetch(FetchDescriptor(predicate: predicate))
        for session in sessions {
            session.status = ScanSessionStatus.interrupted.rawValue
        }
        if !sessions.isEmpty {
            try modelContext.save()
        }
    }

    func recordIndexedPhoto(sessionId: UUID, assetLocalId: String, vectorUUID: String, dimensions: Int, pixelWidth: Int, pixelHeight: Int, creationDate: Date?) throws {
        let predicate = #Predicate<ScanSessionEntity> { $0.id == sessionId }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.fetchLimit = 1
        let session = try modelContext.fetch(descriptor).first

        let existing = #Predicate<PhotoPointEntity> { $0.assetLocalId == assetLocalId }
        let existingDescriptor = FetchDescriptor(predicate: existing)
        guard try modelContext.fetch(existingDescriptor).isEmpty else { return }

        let point = PhotoPointEntity(
            assetLocalId: assetLocalId,
            vectorUUID: vectorUUID,
            embeddingDimensions: dimensions,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            creationDate: creationDate,
            session: session
        )
        modelContext.insert(point)
        try modelContext.save()
    }

    func saveDuplicateGroups(_ groups: [DuplicateGroup], sessionId: UUID) throws {
        let predicate = #Predicate<ScanSessionEntity> { $0.id == sessionId }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.fetchLimit = 1
        let session = try modelContext.fetch(descriptor).first

        for group in groups {
            let entity = DuplicateGroupEntity(session: session)
            modelContext.insert(entity)

            for photo in group.photos {
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
    }

    func loadPendingGroups() throws -> [DuplicateGroupDTO] {
        let pendingStatus = DuplicateGroupStatus.pending.rawValue
        let predicate = #Predicate<DuplicateGroupEntity> { $0.status == pendingStatus }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.sortBy = [SortDescriptor(\.detectedAt, order: .forward)]
        let entities = try modelContext.fetch(descriptor)
        return entities.map { $0.toDTO() }
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
        let predicate = #Predicate<DuplicateGroupEntity> { $0.id == groupId }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.fetchLimit = 1
        guard let entity = try modelContext.fetch(descriptor).first else { return }
        entity.status = DuplicateGroupStatus.reviewed.rawValue
        for member in entity.members {
            member.isKept = keptVectorUUIDs.contains(member.vectorUUID)
        }
        try modelContext.save()
    }

    func markGroupDeleted(groupId: UUID, keptVectorUUIDs: Set<String>, deletedVectorUUIDs: Set<String>) throws {
        let predicate = #Predicate<DuplicateGroupEntity> { $0.id == groupId }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.fetchLimit = 1
        guard let entity = try modelContext.fetch(descriptor).first else { return }
        entity.status = DuplicateGroupStatus.deleted.rawValue
        for member in entity.members {
            if keptVectorUUIDs.contains(member.vectorUUID) {
                member.isKept = true
            } else if deletedVectorUUIDs.contains(member.vectorUUID) {
                member.isKept = false
            }
        }
        try modelContext.save()
    }

    func deleteAllPendingGroups() throws {
        let pendingStatus = DuplicateGroupStatus.pending.rawValue
        let predicate = #Predicate<DuplicateGroupEntity> { $0.status == pendingStatus }
        let entities = try modelContext.fetch(FetchDescriptor(predicate: predicate))
        for entity in entities {
            modelContext.delete(entity)
        }
        try modelContext.save()
    }

    // MARK: - Similarity Edges

    func recordSimilarityEdge(source: String, target: String, score: Float, sessionId: UUID) throws {
        let predicate = #Predicate<ScanSessionEntity> { $0.id == sessionId }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.fetchLimit = 1
        let session = try modelContext.fetch(descriptor).first

        let edge = SimilarityEdgeEntity(
            sourceVectorUUID: source,
            targetVectorUUID: target,
            score: score,
            session: session
        )
        modelContext.insert(edge)
        try modelContext.save()
    }

    func computeGroupsFromEdges(sessionId: UUID) throws -> [DuplicateGroup] {
        let predicate = #Predicate<SimilarityEdgeEntity> { $0.session?.id == sessionId }
        let edges = try modelContext.fetch(FetchDescriptor(predicate: predicate))

        guard !edges.isEmpty else { return [] }

        var unionFind = UnionFind<String>()
        var allScores: [String: Float] = [:]

        for edge in edges {
            _ = unionFind.find(edge.sourceVectorUUID)
            _ = unionFind.find(edge.targetVectorUUID)
            unionFind.union(edge.sourceVectorUUID, edge.targetVectorUUID)
            allScores[edge.targetVectorUUID] = max(
                allScores[edge.targetVectorUUID, default: 0],
                edge.score
            )
            allScores[edge.sourceVectorUUID] = max(
                allScores[edge.sourceVectorUUID, default: 0],
                edge.score
            )
        }

        let components = unionFind.components()

        let allVectorUUIDs = Set(edges.flatMap { [$0.sourceVectorUUID, $0.targetVectorUUID] })
        let photoPoints = try modelContext.fetch(FetchDescriptor<PhotoPointEntity>())
        let pointsByUUID = Dictionary(
            photoPoints.map { ($0.vectorUUID, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        let groups: [DuplicateGroup] = components.compactMap { component in
            let photos: [PhotoReference] = component.compactMap { uuid in
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
            return DuplicateGroup(
                id: UUID().uuidString,
                photos: photos.sorted(by: { $0.megapixels > $1.megapixels }),
                bestCandidate: best
            )
        }

        let sessionPredicate = #Predicate<ScanSessionEntity> { $0.id == sessionId }
        var sessionDescriptor = FetchDescriptor(predicate: sessionPredicate)
        sessionDescriptor.fetchLimit = 1
        let session = try modelContext.fetch(sessionDescriptor).first

        let pendingStatus = DuplicateGroupStatus.pending.rawValue
        let existingPredicate = #Predicate<DuplicateGroupEntity> {
            $0.session?.id == sessionId && $0.status == pendingStatus
        }
        let existingGroups = try modelContext.fetch(FetchDescriptor(predicate: existingPredicate))
        for existing in existingGroups {
            modelContext.delete(existing)
        }

        for group in groups {
            let entity = DuplicateGroupEntity(session: session)
            modelContext.insert(entity)

            for photo in group.photos {
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

        return groups.sorted(by: { $0.count > $1.count })
    }

    nonisolated func countNewPhotosSince(date: Date, in dateRange: DateRange, using photoLibrary: any PhotoLibraryProviding) async throws -> Int {
        let newRange = DateRange(start: date, end: dateRange.end)
        return try await photoLibrary.countAssets(in: newRange)
    }

    func totalPhotosIndexed() throws -> Int {
        let descriptor = FetchDescriptor<PhotoPointEntity>()
        return try modelContext.fetchCount(descriptor)
    }

    func totalDuplicateGroupsFound() throws -> Int {
        let descriptor = FetchDescriptor<DuplicateGroupEntity>()
        return try modelContext.fetchCount(descriptor)
    }

    func totalPhotosDeleted() throws -> Int {
        let deletedStatus = DuplicateGroupStatus.deleted.rawValue
        let predicate = #Predicate<DuplicateGroupEntity> { $0.status == deletedStatus }
        let descriptor = FetchDescriptor(predicate: predicate)
        let groups = try modelContext.fetch(descriptor)
        return groups.reduce(0) { total, group in
            total + group.members.filter { $0.isKept == false }.count
        }
    }
}
