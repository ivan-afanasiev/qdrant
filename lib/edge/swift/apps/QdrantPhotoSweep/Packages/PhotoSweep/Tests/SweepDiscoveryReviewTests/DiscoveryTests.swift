import Foundation
import Testing
import SweepDomain
import SweepPersistence
import SweepTestSupport
import SweepUseCases

@Suite struct DiscoveryChainAndScopeTests {
    @Test func chainsGroupWithoutAllPairsAndNewestSeedComesFirst() async throws {
        let world = try await World([
            SeededPhoto(id: "a", day: 3, degrees: 0),
            SeededPhoto(id: "b", day: 2, degrees: 20),
            SeededPhoto(id: "c", day: 1, degrees: 40),   // matches b, not a: still one group
            SeededPhoto(id: "e", day: 6, degrees: 120),
            SeededPhoto(id: "f", day: 5, degrees: 125),
            SeededPhoto(id: "lonely", day: 9, degrees: 250),
        ])
        let discovery = try world.discovery()
        await world.refill(discovery)

        #expect(try await world.freshGroups() == [["e", "f"], ["a", "b", "c"]])
        #expect(discovery.current.status == .exhausted)
    }

    @Test func groupsLargerThanAnySearchPageAreComplete() async throws {
        let photos = (0..<25).map { SeededPhoto(id: "p\($0)", day: $0 + 1, degrees: Double($0) * 0.2) }
        let world = try await World(photos)
        await world.refill(try world.discovery(pageSize: 4))
        #expect(try await world.freshGroups() == [Set(photos.map(\.id))])
    }

    @Test func outOfScopePhotosNeverJoinOrBridgeGroups() async throws {
        let scope = DateRange(start: World.date(1) ?? .distantPast, end: World.date(10) ?? .distantFuture)
        let world = try await World([
            SeededPhoto(id: "a", day: 2, degrees: 0),
            SeededPhoto(id: "bridge", day: 50, degrees: 20),
            SeededPhoto(id: "c", day: 3, degrees: 40),
            SeededPhoto(id: "twin", day: 60, degrees: 1),
            SeededPhoto(id: "undated", day: nil, degrees: 2),
        ], scope: scope)
        let discovery = try world.discovery()
        await world.refill(discovery)
        #expect(try await world.freshGroups().isEmpty)
        #expect(discovery.current.status == .exhausted)
    }

    @Test func waitsForInitialGate() async throws {
        let world = try await World([SeededPhoto(id: "a", day: 1, degrees: 0), SeededPhoto(id: "b", day: 2, degrees: 1)])
        try await world.store.modifyWorkflowState { $0.gate = InitialPassGate() }
        let discovery = try world.discovery()
        await world.refill(discovery)
        #expect(discovery.current.status == .waitingForInitialPass)
        #expect(try await world.freshGroups().isEmpty)
    }
}

@Suite struct DiscoveryBufferTests {
    /// Four separate pairs, newest pair first.
    func pairs() -> [SeededPhoto] {
        var photos: [SeededPhoto] = []
        for index in 0..<4 {
            let angle = Double(index) * 90
            let newest = 20 - index * 2
            photos.append(SeededPhoto(id: "g\(index)a", day: newest, degrees: angle))
            photos.append(SeededPhoto(id: "g\(index)b", day: newest - 1, degrees: angle + 3))
        }
        return photos
    }

    @Test func stopsWhenBufferIsFullWithoutExaminingEverything() async throws {
        let world = try await World(pairs())
        let discovery = try world.discovery(capacity: 2)
        await world.refill(discovery)

        #expect(try await world.freshGroups() == [["g0a", "g0b"], ["g1a", "g1b"]])
        #expect(discovery.current.status == .bufferReady)
        // Lazy: older photos were not examined yet.
        #expect(try await world.store.nextSeed(revision: DiscoveryRevision(1), scope: DateRange(start: .distantPast, end: .distantFuture), generation: IndexGeneration(1)) != nil)
    }

    @Test func reviewingRefillsUntilTrueExhaustion() async throws {
        let world = try await World(pairs())
        let discovery = try world.discovery(capacity: 2)
        await world.refill(discovery)
        let commit = world.commit(refilling: discovery)

        for _ in 0..<4 {
            let card = try #require(try await world.loadNext.execute())
            #expect(await commit.execute(card, .keepAll, OperationID(world.ids.makeUUID())) == .completed)
            await discovery.waitUntilIdle()
        }
        #expect(try await world.loadNext.execute() == nil)
        #expect(discovery.current.status == .exhausted)
        #expect(try await world.store.statistics().reviewedGroups == 4)
    }

    @Test func backgroundSuspendsAndForegroundResumes() async throws {
        let world = try await World(pairs())
        let discovery = try world.discovery()
        await discovery.setPresence(.background)
        await world.refill(discovery)
        #expect(discovery.current.status == .suspended)
        #expect(try await world.freshGroups().isEmpty)

        await discovery.setPresence(.foreground)
        await discovery.waitUntilIdle()
        #expect(try await world.freshGroups().count == 3)
    }

    @Test func interruptedComponentResumesFromCheckpoint() async throws {
        let world = try await World([
            SeededPhoto(id: "a", day: 3, degrees: 0),
            SeededPhoto(id: "b", day: 2, degrees: 20),
            SeededPhoto(id: "c", day: 1, degrees: 40),
        ])
        // Simulate a relaunch after "a" was queried and "b" found, before "b" was queried.
        guard let threshold = SimilarityThreshold(0.9) else { return }
        let snapshot = ComponentExpansion.Snapshot(
            seed: AssetID("a"), scope: DateRange(start: .distantPast, end: .distantFuture), threshold: threshold,
            generation: IndexGeneration(1), visited: [AssetID("a"), AssetID("b")], queriedCount: 1
        )
        try await world.store.saveDiscoveryProgress(DiscoveryProgress(revision: DiscoveryRevision(1), seedCursor: AssetID("a"), expansion: snapshot))
        try world.relaunch()

        let discovery = try world.discovery()
        await world.refill(discovery)
        #expect(try await world.freshGroups() == [["a", "b", "c"]])
        // The resumed component did not re-query its already-finished seed from scratch.
        #expect(try await world.vectors().searchPageCount <= 3)
    }
}

@Suite struct IncrementalArrivalTests {
    @Test func newPhotosAfterExhaustionFormNewGroups() async throws {
        let world = try await World([SeededPhoto(id: "a", day: 1, degrees: 0), SeededPhoto(id: "b", day: 2, degrees: 2)])
        let discovery = try world.discovery()
        await world.refill(discovery)
        #expect(discovery.current.status == .exhausted)

        try await world.add([SeededPhoto(id: "n1", day: 5, degrees: 90), SeededPhoto(id: "n2", day: 6, degrees: 92)])
        await world.refill(discovery)
        #expect(try await world.freshGroups() == [["a", "b"], ["n1", "n2"]])
    }

    @Test func newMatchForPendingGroupMergesKeepingIdentity() async throws {
        let world = try await World([SeededPhoto(id: "a", day: 1, degrees: 0), SeededPhoto(id: "b", day: 2, degrees: 2)])
        let discovery = try world.discovery()
        await world.refill(discovery)
        let original = try #require(try await world.loadNext.execute())

        try await world.add([SeededPhoto(id: "new", day: 5, degrees: 4)])
        await world.refill(discovery)
        let merged = try #require(try await world.store.group(original.id))
        #expect(merged.revision == MembershipRevision(2))
        #expect(Set(merged.members.map(\.rawValue)) == ["a", "b", "new"])
        #expect(try await world.freshGroups().count == 1)
    }

    @Test func newMatchForReviewedGroupDoesNotResurface() async throws {
        let world = try await World([SeededPhoto(id: "a", day: 1, degrees: 0), SeededPhoto(id: "b", day: 2, degrees: 2)])
        let discovery = try world.discovery()
        await world.refill(discovery)
        let card = try #require(try await world.loadNext.execute())
        #expect(await world.commit(refilling: discovery).execute(card, .keepAll, OperationID(world.ids.makeUUID())) == .completed)
        await discovery.waitUntilIdle()

        try await world.add([SeededPhoto(id: "new", day: 5, degrees: 1)])
        await world.refill(discovery)
        #expect(try await world.freshGroups().isEmpty)
        #expect(try await world.loadNext.execute() == nil)
    }

    @Test func twoPendingGroupsJoinedByNewPhotoBecomeOneWithLineage() async throws {
        let world = try await World([
            SeededPhoto(id: "a", day: 1, degrees: 0), SeededPhoto(id: "b", day: 2, degrees: 3),
            SeededPhoto(id: "c", day: 3, degrees: 40), SeededPhoto(id: "d", day: 4, degrees: 43),
        ])
        let discovery = try world.discovery()
        await world.refill(discovery)
        let before = try await world.store.reviewQueue(for: DiscoveryRevision(1)).fresh
        #expect(before.count == 2)

        try await world.add([SeededPhoto(id: "bridge", day: 9, degrees: 21)])
        await world.refill(discovery)
        let after = try await world.store.reviewQueue(for: DiscoveryRevision(1)).fresh
        #expect(after.count == 1)
        let joined = try #require(after.first)
        #expect(Set(try await world.store.lineage(of: joined)) == Set(before))
        #expect(try await world.freshGroups() == [["a", "b", "c", "d", "bridge"]])
    }
}

@Suite struct DiscoveryRevisionTests {
    @Test func thresholdChangeOrRescanResetsOrderAndDeferrals() async throws {
        let world = try await World([
            SeededPhoto(id: "a", day: 1, degrees: 0), SeededPhoto(id: "b", day: 2, degrees: 2),
            SeededPhoto(id: "c", day: 3, degrees: 90), SeededPhoto(id: "d", day: 4, degrees: 92),
        ])
        let discovery = try world.discovery()
        await world.refill(discovery)
        let first = try #require(try await world.loadNext.execute())
        #expect(await world.skip(refilling: discovery).execute(first) == .persisted)
        await discovery.waitUntilIdle()

        let revision = try await discovery.beginNewRevision()
        await discovery.waitUntilIdle()
        #expect(revision == DiscoveryRevision(2))
        #expect(try await world.store.reviewQueue(for: DiscoveryRevision(2)).deferred.isEmpty)
        #expect(try await world.freshGroups(revision: 2) == [["c", "d"], ["a", "b"]])
        #expect(try await world.store.group(first.id) == nil)
    }
}
