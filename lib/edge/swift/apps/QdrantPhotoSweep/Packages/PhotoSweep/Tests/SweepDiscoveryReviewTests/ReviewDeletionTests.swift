import CoreGraphics
import Foundation
import Testing
import SweepDomain
import SweepFeatureState
import SweepPersistence
import SweepReviewFeature
import SweepTestSupport
import SweepUseCases

/// Two pairs: (a, b) newest, then (c, d).
private func twoPairs() async throws -> (World, DiscoveryExecutor) {
    let world = try await World([
        SeededPhoto(id: "a", day: 4, degrees: 0), SeededPhoto(id: "b", day: 3, degrees: 2, fileSize: 400),
        SeededPhoto(id: "c", day: 2, degrees: 90), SeededPhoto(id: "d", day: 1, degrees: 92),
    ])
    let discovery = try world.discovery()
    await world.refill(discovery)
    return (world, discovery)
}

private func ids(_ names: String...) -> Set<AssetID> {
    Set(names.map(AssetID.init))
}

@Suite struct ReviewOrderTests {
    @Test func skippedGroupReturnsOnlyAfterEverythingElse() async throws {
        let (world, discovery) = try await twoPairs()
        let first = try #require(try await world.loadNext.execute())
        #expect(Set(first.members) == ids("a", "b"))
        #expect(await world.skip(refilling: discovery).execute(first) == .persisted)
        await discovery.waitUntilIdle()

        let second = try #require(try await world.loadNext.execute())
        #expect(Set(second.members) == ids("c", "d"))
        #expect(await world.commit(refilling: discovery).execute(second, .keepAll, OperationID(world.ids.makeUUID())) == .completed)
        await discovery.waitUntilIdle()

        #expect(try await world.loadNext.execute()?.id == first.id)
    }

    @Test func keepAllCompletesWithoutDeleting() async throws {
        let (world, discovery) = try await twoPairs()
        let card = try #require(try await world.loadNext.execute())
        #expect(await world.commit(refilling: discovery).execute(card, .keepAll, OperationID(world.ids.makeUUID())) == .completed)
        #expect(await world.library.deletedIdentifiers.isEmpty)
        #expect(try await world.store.statistics().reviewedGroups == 1)
    }

    @Test func fullResolutionOnlyForPreview() async throws {
        let (world, _) = try await twoPairs()
        let images = LoadReviewImage(library: world.library)
        _ = try await images.thumbnail(AssetID("a"), pixels: 300)
        #expect(await world.library.fullResolutionRequestCount == 0)
        _ = try await images.preview(AssetID("a"))
        #expect(await world.library.fullResolutionRequestCount == 1)
    }
}

@Suite struct DeletionTests {
    @Test func deletingSelectedPhotosCleansUpAndCountsOnce() async throws {
        let (world, discovery) = try await twoPairs()
        let card = try #require(try await world.loadNext.execute())
        let decision = try KeepSelectionPolicy.validate(.keep(ids("a")), for: card)

        #expect(await world.commit(refilling: discovery).execute(card, decision, OperationID(world.ids.makeUUID())) == .completed)
        await discovery.waitUntilIdle()
        #expect(await world.library.deletedIdentifiers == [["b"]])
        #expect(try await world.store.assets([AssetID("b")]).isEmpty)
        #expect(try await world.vectors().count() == 3)
        #expect(try await world.store.openJournalEntries().isEmpty)
        let stats = try await world.store.statistics()
        #expect(stats.deletedPhotos == 1)
        #expect(stats.reviewedGroups == 1)
        #expect(stats.estimatedBytesFreed == 400)
        #expect(Set(try #require(try await world.loadNext.execute()).members) == ids("c", "d"))
    }

    @Test func explicitDeleteAllRemovesEveryPhoto() async throws {
        let (world, discovery) = try await twoPairs()
        let card = try #require(try await world.loadNext.execute())
        let decision = try KeepSelectionPolicy.validate(.deleteAll, for: card)
        #expect(await world.commit(refilling: discovery).execute(card, decision, OperationID(world.ids.makeUUID())) == .completed)
        #expect(Set(await world.library.deletedIdentifiers.flatMap { $0 }) == ["a", "b"])
        #expect(try await world.store.statistics().deletedPhotos == 2)
    }

    @Test func declinedDeletionKeepsCardAndCountsNothing() async throws {
        let (world, discovery) = try await twoPairs()
        await world.library.setDeletionError(.deletionDeclined)
        let card = try #require(try await world.loadNext.execute())
        let decision = try KeepSelectionPolicy.validate(.deleteAll, for: card)

        #expect(await world.commit(refilling: discovery).execute(card, decision, OperationID(world.ids.makeUUID())) == .deletionDeclined)
        #expect(try await world.store.openJournalEntries().isEmpty)
        #expect(try await world.store.statistics() == LibraryStatistics(vectorizedPhotos: 4, unavailablePhotos: 0, reviewedGroups: 0, deletedPhotos: 0, estimatedBytesFreed: 0, deletionsWithUnknownSize: 0))
        #expect(try await world.loadNext.execute()?.id == card.id)
    }

    @Test func staleCardIsAConflictNotASilentDeletion() async throws {
        let (world, discovery) = try await twoPairs()
        let card = try #require(try await world.loadNext.execute())
        try await world.add([SeededPhoto(id: "new", day: 9, degrees: 1)])
        await world.refill(discovery)

        let decision = try KeepSelectionPolicy.validate(.deleteAll, for: card)
        #expect(await world.commit(refilling: discovery).execute(card, decision, OperationID(world.ids.makeUUID())) == .conflict)
        #expect(await world.library.deletedIdentifiers.isEmpty)
        let refreshed = try #require(try await world.loadNext.execute())
        #expect(refreshed.id == card.id)
        #expect(refreshed.revision > card.revision)
    }

    @Test func photoMadeInaccessibleOutsideTheAppIsAConflict() async throws {
        let (world, discovery) = try await twoPairs()
        let card = try #require(try await world.loadNext.execute())
        await world.library.setAssets(await world.library.assets.filter { $0.id != "b" })
        let decision = try KeepSelectionPolicy.validate(.keep(ids("a")), for: card)
        #expect(await world.commit(refilling: discovery).execute(card, decision, OperationID(world.ids.makeUUID())) == .conflict)
        #expect(await world.library.deletedIdentifiers.isEmpty)
    }

    @Test func failedCallThatStillDeletedIsReconciledAsDone() async throws {
        let (world, discovery) = try await twoPairs()
        await world.library.setDeletionError(.deletion("connection interrupted"))
        await world.library.setDeletesBeforeFailing(true)
        let card = try #require(try await world.loadNext.execute())
        let decision = try KeepSelectionPolicy.validate(.keep(ids("a")), for: card)
        #expect(await world.commit(refilling: discovery).execute(card, decision, OperationID(world.ids.makeUUID())) == .completed)
        #expect(try await world.store.statistics().deletedPhotos == 1)
        #expect(try await world.store.openJournalEntries().isEmpty)
    }

    @Test func cleanupFailureHidesCardUntilRecoveryFinishes() async throws {
        let (world, discovery) = try await twoPairs()
        let card = try #require(try await world.loadNext.execute())
        try await world.vectors().setFailure(.vectorStore("disk full"))
        let decision = try KeepSelectionPolicy.validate(.keep(ids("a")), for: card)

        guard case .failed = await world.commit(refilling: discovery).execute(card, decision, OperationID(world.ids.makeUUID())) else {
            Issue.record("Expected cleanup failure to be reported")
            return
        }
        #expect(await world.library.deletedIdentifiers == [["b"]])
        #expect(try await world.loadNext.execute()?.id != card.id)

        try await world.vectors().setFailure(nil)
        try world.relaunch()
        let report = try await world.recovery().execute()
        #expect(report.finishedDeletions.count == 1)
        #expect(try await world.store.statistics().deletedPhotos == 1)
        // Photos is never asked to delete again during recovery.
        #expect(await world.library.deletedIdentifiers == [["b"]])
    }
}

@Suite struct DeletionCrashRecoveryTests {
    /// Journals a deletion of "b" from the (a, b) group, as the commit would before asking Photos.
    func journaled(_ world: World) async throws -> OperationID {
        let card = try #require(try await world.loadNext.execute())
        let operation = OperationID(world.ids.makeUUID())
        try await world.store.beginDeletion(operation, group: card.id, revision: card.revision, assets: [AssetID("b")], estimatedBytes: 400)
        return operation
    }

    @Test func crashBeforePhotosCallRestoresTheCard() async throws {
        let (world, _) = try await twoPairs()
        let operation = try await journaled(world)
        #expect(Set(try #require(try await world.loadNext.execute()).members) == ids("c", "d"))

        try world.relaunch()
        let report = try await world.recovery().execute()
        #expect(report.abandonedDeletions == [operation])
        #expect(try await world.store.statistics().deletedPhotos == 0)
        #expect(Set(try #require(try await world.loadNext.execute()).members) == ids("a", "b"))
    }

    @Test func crashAfterPhotosDeletedBeforeConfirmationIsReconciled() async throws {
        let (world, _) = try await twoPairs()
        let operation = try await journaled(world)
        try await world.library.deleteAssets(["b"])

        try world.relaunch()
        let report = try await world.recovery().execute()
        #expect(report.finishedDeletions == [operation])
        let stats = try await world.store.statistics()
        #expect(stats.deletedPhotos == 1)
        #expect(stats.estimatedBytesFreed == 400)
        #expect(try await world.store.assets([AssetID("b")]).isEmpty)
    }

    @Test func limitedAccessIsNeverProofOfDeletion() async throws {
        let (world, _) = try await twoPairs()
        let operation = try await journaled(world)
        try await world.library.deleteAssets(["b"])
        await world.library.setAccessScope(.limited)

        try world.relaunch()
        let report = try await world.recovery().execute()
        #expect(report.pendingDeletions == [operation])
        #expect(try await world.store.statistics().deletedPhotos == 0)
        // The group stays hidden while its deletion is unresolved.
        #expect(Set(try #require(try await world.loadNext.execute()).members) == ids("c", "d"))
    }

    @Test func crashAfterConfirmationFinishesCleanupOnceWithoutDeletingAgain() async throws {
        let (world, _) = try await twoPairs()
        let operation = try await journaled(world)
        try await world.library.deleteAssets(["b"])
        try await world.store.confirmExternalDeletion(operation)

        try world.relaunch()
        #expect(try await world.recovery().execute().finishedDeletions == [operation])
        #expect(try await world.recovery().execute() == RecoveryReport())
        #expect(try await world.store.statistics().deletedPhotos == 1)
        #expect(await world.library.deletedIdentifiers == [["b"]])
    }
}

@MainActor
@Suite struct ReviewFeatureIntegrationTests {
    @Test func cardReducerDrivesRealUseCases() async throws {
        let (world, discovery) = try await twoPairs()
        let client = ReviewClient.live(
            discovery: discovery,
            loadNext: world.loadNext,
            skip: world.skip(refilling: discovery),
            commit: world.commit(refilling: discovery),
            ids: world.ids
        )
        let store = Store(initialState: ReviewFeature.State(), reducer: ReviewFeature(client: client))
        store.send(.discoveryUpdated(discovery.current))
        await store.finishAllEffects()
        let card = try #require(store.state.card)
        #expect(Set(card.snapshot.members) == ids("a", "b"))
        #expect(card.keep.isEmpty)

        store.send(.keepToggled(AssetID("a")))
        store.send(.commitTapped)
        await store.finishAllEffects()
        await discovery.waitUntilIdle()
        #expect(await world.library.deletedIdentifiers == [["b"]])
        #expect(Set(try #require(store.state.card).snapshot.members) == ids("c", "d"))
    }
}
