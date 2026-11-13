import Foundation
import Testing
import SweepDomain
import SweepPersistence
import SweepTestSupport

private func publish(_ store: SwiftDataMetadataStore, _ group: ReviewGroupSnapshot, cursor: String? = nil) async throws {
    try await store.publishGroup(
        group,
        derivedFrom: [],
        progress: DiscoveryProgress(revision: group.discoveryRevision, seedCursor: cursor.map(AssetID.init))
    )
}

@Suite struct ReviewPersistenceTests {
    @Test func publishingSavesGroupMembershipQueueAndProgressTogether() async throws {
        let file = try TemporaryStore()
        try await publish(try file.open(), snapshot(1, members: ["a", "b", "c"]), cursor: "a")

        let reopened = try file.open()
        #expect(try await reopened.group(groupID(1)) == snapshot(1, members: ["a", "b", "c"]))
        #expect(try await reopened.reviewQueue(for: DiscoveryRevision(1)) == ReviewQueue(fresh: [groupID(1)]))
        #expect(try await reopened.discoveryProgress(for: DiscoveryRevision(1))?.seedCursor == AssetID("a"))
    }

    @Test func publishingTheSameGroupTwiceIsRejected() async throws {
        let store = try TemporaryStore().open()
        try await publish(store, snapshot(1, members: ["a", "b"]))
        await #expect(throws: PersistenceError.self) {
            try await publish(store, snapshot(1, members: ["a", "b"]))
        }
    }

    @Test func skipOrderIsDurableAndCyclesWithoutDuplicates() async throws {
        let file = try TemporaryStore()
        let store = try file.open()
        for id in UInt64(1)...3 {
            try await publish(store, snapshot(id, members: ["a\(id)", "b\(id)"]))
        }
        try await store.deferGroup(groupID(2))
        try await store.deferGroup(groupID(1))
        #expect(try await file.open().reviewQueue(for: DiscoveryRevision(1)) == ReviewQueue(fresh: [groupID(3)], deferred: [groupID(2), groupID(1)]))

        // Skipping a deferred group again moves it to the end, still once.
        try await store.deferGroup(groupID(2))
        #expect(try await file.open().reviewQueue(for: DiscoveryRevision(1)).deferred == [groupID(1), groupID(2)])
    }

    @Test func sameCountMembershipChangeBumpsRevision() async throws {
        let store = try TemporaryStore().open()
        try await publish(store, snapshot(1, members: ["a", "b"]))
        let updated = try await store.updateMembership(of: groupID(1), members: [AssetID("a"), AssetID("c")])
        #expect(updated.revision == MembershipRevision(2))
        #expect(try await store.group(groupID(1)) == updated)
        #expect(throws: ReviewError.conflict(groupID(1))) {
            try ReviewCommitPolicy.validateCurrent(snapshot(1, members: ["a", "b"]), currentRevision: updated.revision, unavailable: [])
        }
    }

    @Test func completionIsIdempotentPerOperationAndSuppressesReviewedMembers() async throws {
        let file = try TemporaryStore()
        let store = try file.open()
        try await publish(store, snapshot(1, members: ["a", "b"]))
        try await store.completeGroup(groupID(1), operation: operation(10))
        try await store.completeGroup(groupID(1), operation: operation(10))
        await #expect(throws: PersistenceError.self) {
            try await store.completeGroup(groupID(1), operation: operation(11))
        }

        let reopened = try file.open()
        #expect(try await reopened.statistics().reviewedGroups == 1)
        #expect(try await reopened.reviewQueue(for: DiscoveryRevision(1)) == ReviewQueue())
        // A new photo matching a reviewed member must not resurface the group.
        #expect(try await reopened.isSuppressed([AssetID("new"), AssetID("b")], revision: DiscoveryRevision(1)))
        #expect(try await !reopened.isSuppressed([AssetID("new"), AssetID("other")], revision: DiscoveryRevision(1)))
        await #expect(throws: PersistenceError.self) {
            _ = try await reopened.updateMembership(of: groupID(1), members: [AssetID("a")])
        }
    }

    @Test func newRevisionRetiresOldGroupsDeferralsAndSuppression() async throws {
        let store = try TemporaryStore().open()
        try await publish(store, snapshot(1, members: ["a", "b"]))
        try await publish(store, snapshot(2, members: ["c", "d"]))
        try await store.completeGroup(groupID(1), operation: operation(10))
        try await store.deferGroup(groupID(2))

        try await store.retireGroups(before: DiscoveryRevision(2))
        #expect(try await store.group(groupID(2)) == nil)
        #expect(try await store.reviewQueue(for: DiscoveryRevision(1)) == ReviewQueue())
        #expect(try await !store.isSuppressed([AssetID("a")], revision: DiscoveryRevision(2)))
        #expect(try await store.discoveryProgress(for: DiscoveryRevision(1)) == nil)
        // Confirmed history is not lost when review order resets.
        #expect(try await store.statistics().reviewedGroups == 1)
    }

    @Test func lineageIsRecorded() async throws {
        let store = try TemporaryStore().open()
        try await store.publishGroup(
            snapshot(3, members: ["a", "b", "c"]),
            derivedFrom: [groupID(1), groupID(2)],
            progress: DiscoveryProgress(revision: DiscoveryRevision(1))
        )
        #expect(try await store.lineage(of: groupID(3)) == [groupID(1), groupID(2)])
    }
}

@Suite struct StatisticsPersistenceTests {
    @Test func confirmedDeletionsAreCountedOncePerOperation() async throws {
        let file = try TemporaryStore()
        let store = try file.open()
        #expect(try await store.recordDeletion(operation(1), photoCount: 2, estimatedBytes: 5_000, revision: DiscoveryRevision(1)))
        #expect(try await !store.recordDeletion(operation(1), photoCount: 2, estimatedBytes: 5_000, revision: DiscoveryRevision(1)))
        #expect(try await file.open().recordDeletion(operation(2), photoCount: 1, estimatedBytes: nil, revision: DiscoveryRevision(2)))

        let stats = try await file.open().statistics()
        #expect(stats.deletedPhotos == 3)
        #expect(stats.estimatedBytesFreed == 5_000)
        #expect(stats.deletionsWithUnknownSize == 1)
    }

    @Test func photoCountsComeFromDurableOutcomes() async throws {
        let store = try TemporaryStore().open()
        let records = try await store.register([discovered("a"), discovered("b"), discovered("c")])
        try await store.beginPass(VectorizationPass(id: passID(1), kind: .initial, scope: scope, workSet: records.map(\.id)))
        try await store.beginVectorWrite(operation(1), intents: [intent(for: records[0])])
        try await store.commitVectorWrite(operation(1), pass: passID(1))
        try await store.recordDeferred([AssetID("b"): .unavailable("iCloud")], pass: passID(1))

        let stats = try await store.statistics()
        #expect(stats.vectorizedPhotos == 1)
        #expect(stats.unavailablePhotos == 1)
    }
}
