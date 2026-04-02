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

    func latestGroupingInterruptedSession() throws -> ScanSessionDTO? {
        let status = ScanSessionStatus.groupingInterrupted.rawValue
        let predicate = #Predicate<ScanSessionEntity> { $0.status == status }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.sortBy = [SortDescriptor(\.scannedAt, order: .reverse)]
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first?.toDTO()
    }

    func interruptActiveSessions() throws {
        let scanningStatus = ScanSessionStatus.scanning.rawValue
        let groupingStatus = ScanSessionStatus.grouping.rawValue
        let predicate = #Predicate<ScanSessionEntity> {
            $0.status == scanningStatus || $0.status == groupingStatus
        }
        let sessions = try modelContext.fetch(FetchDescriptor(predicate: predicate))
        for session in sessions {
            switch session.status {
            case scanningStatus:
                session.status = ScanSessionStatus.interrupted.rawValue
            case groupingStatus:
                session.status = ScanSessionStatus.groupingInterrupted.rawValue
            default:
                session.status = ScanSessionStatus.interrupted.rawValue
            }
        }
        if !sessions.isEmpty {
            try modelContext.save()
        }
    }

    func recordIndexedPhoto(sessionId: UUID, assetLocalId: String, vectorUUID: String, dimensions: Int) throws {
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
