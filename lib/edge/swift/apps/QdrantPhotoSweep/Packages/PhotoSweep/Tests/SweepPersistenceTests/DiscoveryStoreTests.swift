import Foundation
import Testing
import SweepDomain
import SweepPersistence
import SweepTestSupport

private func dated(_ name: String, day: Int?) -> DiscoveredAsset {
    DiscoveredAsset(
        id: AssetID(name),
        creationDate: day.map { Date(timeIntervalSince1970: Double($0) * 86_400) },
        contentRevision: AssetContentRevision("r1")
    )
}

/// Registers and commits vectors in generation 1 for the given assets.
private func vectorized(_ store: SwiftDataMetadataStore, _ assets: [DiscoveredAsset], operation value: UInt64 = 1) async throws {
    let records = try await store.register(assets)
    try await store.beginVectorWrite(operation(value), intents: records.map(intent(for:)))
    try await store.commitVectorWrite(operation(value), pass: nil)
}

private let revision1 = DiscoveryRevision(1)

@Suite struct SeedOrderTests {
    @Test func seedsAreNewestFirstAndSkipExaminedPhotos() async throws {
        let store = try TemporaryStore().open()
        try await vectorized(store, [dated("old", day: 1), dated("new", day: 9), dated("mid", day: 5)])

        #expect(try await store.nextSeed(revision: revision1, scope: scope, generation: generation)?.id == AssetID("new"))
        try await store.completeComponent(members: [AssetID("new")], outcome: .discarded, progress: DiscoveryProgress(revision: revision1))
        #expect(try await store.nextSeed(revision: revision1, scope: scope, generation: generation)?.id == AssetID("mid"))
        try await store.completeComponent(members: [AssetID("mid"), AssetID("old")], outcome: .discarded, progress: DiscoveryProgress(revision: revision1))
        #expect(try await store.nextSeed(revision: revision1, scope: scope, generation: generation) == nil)

        // A new revision (threshold change, rescan) examines everything again.
        #expect(try await store.nextSeed(revision: DiscoveryRevision(2), scope: scope, generation: generation)?.id == AssetID("new"))
    }

    @Test func onlyCommittedInScopeDatedVectorsOfTheGenerationAreSeeds() async throws {
        let store = try TemporaryStore().open()
        try await vectorized(store, [dated("ok", day: 3), dated("undated", day: nil), dated("outside", day: 400)])
        _ = try await store.register([dated("pending", day: 8)])
        #expect(try await store.nextSeed(revision: revision1, scope: scope, generation: generation)?.id == AssetID("ok"))
        #expect(try await store.nextSeed(revision: revision1, scope: scope, generation: IndexGeneration(2)) == nil)
    }

    @Test func editedPhotoIsExaminedAgainAfterRevectorization() async throws {
        let store = try TemporaryStore().open()
        try await vectorized(store, [dated("a", day: 3)])
        try await store.completeComponent(members: [AssetID("a")], outcome: .discarded, progress: DiscoveryProgress(revision: revision1))
        let edited = DiscoveredAsset(id: AssetID("a"), creationDate: Date(timeIntervalSince1970: 3 * 86_400), contentRevision: AssetContentRevision("r2"))
        try await vectorized(store, [edited], operation: 2)
        #expect(try await store.nextSeed(revision: revision1, scope: scope, generation: generation)?.id == AssetID("a"))
    }
}

@Suite struct ComponentOutcomeTests {
    @Test func publishingCreatesFreshGroupAndRetiresAbsorbedGroups() async throws {
        let file = try TemporaryStore()
        let store = try file.open()
        try await store.publishGroup(snapshot(1, members: ["a", "b"]), derivedFrom: [], progress: DiscoveryProgress(revision: revision1))
        try await store.publishGroup(snapshot(2, members: ["c", "d"]), derivedFrom: [], progress: DiscoveryProgress(revision: revision1))
        #expect(try await store.pendingGroups(containing: [AssetID("b"), AssetID("c")], revision: revision1) == [groupID(1), groupID(2)])

        let merged = snapshot(3, members: ["a", "b", "x", "c", "d"])
        try await store.completeComponent(members: merged.members, outcome: .published(merged, derivedFrom: [groupID(1), groupID(2)]), progress: DiscoveryProgress(revision: revision1))

        let reopened = try file.open()
        #expect(try await reopened.reviewQueue(for: revision1) == ReviewQueue(fresh: [groupID(3)]))
        #expect(try await reopened.lineage(of: groupID(3)) == [groupID(1), groupID(2)])
        #expect(try await reopened.group(groupID(1)) == nil)
    }

    @Test func mergingKeepsIdentityAndBumpsRevision() async throws {
        let store = try TemporaryStore().open()
        try await store.publishGroup(snapshot(1, members: ["a", "b"]), derivedFrom: [], progress: DiscoveryProgress(revision: revision1))
        try await store.completeComponent(
            members: [AssetID("a"), AssetID("b"), AssetID("new")],
            outcome: .merged(into: groupID(1), members: [AssetID("new"), AssetID("a"), AssetID("b")]),
            progress: DiscoveryProgress(revision: revision1)
        )
        let group = try #require(try await store.group(groupID(1)))
        #expect(group.revision == MembershipRevision(2))
        #expect(group.members == [AssetID("new"), AssetID("a"), AssetID("b")])
    }

    @Test func completedGroupsAreNotPendingAndCannotAbsorb() async throws {
        let store = try TemporaryStore().open()
        try await store.publishGroup(snapshot(1, members: ["a", "b"]), derivedFrom: [], progress: DiscoveryProgress(revision: revision1))
        try await store.completeGroup(groupID(1), operation: operation(5))
        #expect(try await store.pendingGroups(containing: [AssetID("a")], revision: revision1).isEmpty)
        await #expect(throws: PersistenceError.self) {
            try await store.completeComponent(members: [AssetID("a")], outcome: .merged(into: groupID(1), members: [AssetID("a")]), progress: DiscoveryProgress(revision: revision1))
        }
    }
}

@Suite struct FinishDeletionTests {
    @Test func finishingRemovesAssetsCompletesGroupAndCountsOnce() async throws {
        let file = try TemporaryStore()
        let store = try file.open()
        try await vectorized(store, [dated("a", day: 1), dated("b", day: 2)])
        try await store.publishGroup(snapshot(1, members: ["a", "b"]), derivedFrom: [], progress: DiscoveryProgress(revision: revision1))
        try await store.beginDeletion(operation(7), group: groupID(1), revision: MembershipRevision(1), assets: [AssetID("b")], estimatedBytes: 300)
        try await store.confirmExternalDeletion(operation(7))

        try await store.finishDeletion(operation(7), deleted: [AssetID("b")], estimatedBytes: 300, revision: revision1)
        // Replaying after a crash must not count twice.
        try await file.open().finishDeletion(operation(7), deleted: [AssetID("b")], estimatedBytes: 300, revision: revision1)

        let reopened = try file.open()
        #expect(try await reopened.assets([AssetID("a"), AssetID("b")]).keys.sorted() == [AssetID("a")])
        #expect(try await reopened.openJournalEntries().isEmpty)
        #expect(try await reopened.reviewQueue(for: revision1) == ReviewQueue())
        let stats = try await reopened.statistics()
        #expect(stats.deletedPhotos == 1)
        #expect(stats.reviewedGroups == 1)
        #expect(stats.estimatedBytesFreed == 300)
        #expect(try await reopened.isSuppressed([AssetID("a")], revision: revision1))
    }

    @Test func deletionForRetiredGroupStillCountsPhotos() async throws {
        let store = try TemporaryStore().open()
        try await vectorized(store, [dated("a", day: 1)])
        try await store.publishGroup(snapshot(1, members: ["a", "b"]), derivedFrom: [], progress: DiscoveryProgress(revision: revision1))
        try await store.beginDeletion(operation(7), group: groupID(1), revision: MembershipRevision(1), assets: [AssetID("a")], estimatedBytes: nil)
        try await store.retireGroups(before: DiscoveryRevision(2))

        try await store.finishDeletion(operation(7), deleted: [AssetID("a")], estimatedBytes: nil, revision: revision1)
        let stats = try await store.statistics()
        #expect(stats.deletedPhotos == 1)
        #expect(stats.reviewedGroups == 0)
        #expect(stats.deletionsWithUnknownSize == 1)
    }
}
