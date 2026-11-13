import Foundation
import Testing
import SweepDomain
import SweepFeatureState
import SweepReviewFeature
import SweepTestSupport

/// Scriptable review backend that records every commit and skip.
private actor ReviewBackend {
    struct Commit: Equatable {
        let group: GroupID
        let decision: ReviewDecision
        let operation: OperationID
    }

    var queue: [ReviewGroupSnapshot]
    var commitOutcome: ReviewCommitOutcome = .completed
    var skipOutcome: SkipOutcome = .persisted
    private(set) var commits: [Commit] = []
    private(set) var skips: [GroupID] = []
    private(set) var loads = 0

    init(queue: [ReviewGroupSnapshot]) {
        self.queue = queue
    }

    func setCommitOutcome(_ outcome: ReviewCommitOutcome) {
        commitOutcome = outcome
    }

    func setSkipOutcome(_ outcome: SkipOutcome) {
        skipOutcome = outcome
    }

    func loadNext() -> ReviewGroupSnapshot? {
        loads += 1
        return queue.isEmpty ? nil : queue.removeFirst()
    }

    func commit(_ snapshot: ReviewGroupSnapshot, _ decision: ReviewDecision, _ operation: OperationID) -> ReviewCommitOutcome {
        commits.append(Commit(group: snapshot.id, decision: decision, operation: operation))
        return commitOutcome
    }

    func skip(_ snapshot: ReviewGroupSnapshot) -> SkipOutcome {
        skips.append(snapshot.id)
        return skipOutcome
    }
}

private func snapshot(_ id: UInt64, revision: Int = 1, discovery: Int = 1, members: [String] = ["a", "b", "c"]) -> ReviewGroupSnapshot {
    ReviewGroupSnapshot(
        id: GroupID(SequentialIDGenerator.uuid(id)),
        revision: MembershipRevision(revision),
        discoveryRevision: DiscoveryRevision(discovery),
        members: members.map(AssetID.init)
    )
}

private func update(_ status: DiscoveryStatus, revision: Int = 1) -> ReviewFeature.Action {
    .discoveryUpdated(DiscoveryUpdate(revision: DiscoveryRevision(revision), status: status))
}

private func operation(_ value: UInt64) -> OperationID {
    OperationID(SequentialIDGenerator.uuid(value))
}

@MainActor
private func makeStore(queue: [ReviewGroupSnapshot]) -> (Store<ReviewFeature>, ReviewBackend) {
    let backend = ReviewBackend(queue: queue)
    let ids = SequentialIDGenerator(startingAt: 100)
    let client = ReviewClient(
        observeDiscovery: { AsyncStream { $0.finish() } },
        loadNextGroup: { await backend.loadNext() },
        skip: { await backend.skip($0) },
        commit: { await backend.commit($0, $1, $2) },
        makeOperationID: { OperationID(ids.makeUUID()) }
    )
    return (Store(initialState: ReviewFeature.State(), reducer: ReviewFeature(client: client)), backend)
}

/// Opens the first card by reporting a ready buffer.
@MainActor
private func openFirstCard(_ store: Store<ReviewFeature>) async {
    store.send(update(.bufferReady))
    await store.finishAllEffects()
}

@MainActor
@Suite struct ReviewFeatureLoadingTests {
    @Test func cardOpensWithNoKeepSelection() async {
        let (store, _) = makeStore(queue: [snapshot(1)])
        await openFirstCard(store)
        #expect(store.state.card == ReviewFeature.Card(snapshot: snapshot(1)))
        #expect(store.state.card?.keep.isEmpty == true)
    }

    @Test(arguments: [DiscoveryStatus.waitingForInitialPass, .suspended, .failed("store")])
    func noLoadingWhileDiscoveryCannotProvideGroups(status: DiscoveryStatus) async {
        let (store, backend) = makeStore(queue: [snapshot(1)])
        store.send(update(status))
        await store.finishAllEffects()
        #expect(store.state.card == nil)
        #expect(await backend.loads == 0)
    }

    @Test func emptyBufferWhileSearchingLeavesNoCardWithoutClaimingExhaustion() async {
        let (store, backend) = makeStore(queue: [])
        store.send(update(.searching))
        await store.finishAllEffects()
        #expect(store.state.card == nil)
        #expect(store.state.discovery?.status == .searching)
        #expect(await backend.loads == 1)
    }

    @Test func openCardIsNeverReplacedByLaterLoad() async {
        let (store, _) = makeStore(queue: [snapshot(1)])
        await openFirstCard(store)
        store.send(.keepToggled(AssetID("a")))
        store.send(.groupLoaded(snapshot(1, revision: 2, members: ["a", "b"])))
        #expect(store.state.card?.snapshot == snapshot(1))
        #expect(store.state.card?.keep == [AssetID("a")])
    }

    @Test func olderDiscoveryUpdatesAreIgnored() {
        let (store, _) = makeStore(queue: [])
        store.send(update(.searching, revision: 2))
        store.send(update(.exhausted, revision: 1))
        #expect(store.state.discovery == DiscoveryUpdate(revision: DiscoveryRevision(2), status: .searching))
    }
}

@MainActor
@Suite struct ReviewFeatureSelectionTests {
    @Test func togglingSelectsOnlyGroupMembers() async {
        let (store, _) = makeStore(queue: [snapshot(1)])
        await openFirstCard(store)
        store.send(.keepToggled(AssetID("a")))
        store.send(.keepToggled(AssetID("outsider")))
        #expect(store.state.card?.keep == [AssetID("a")])
        store.send(.keepToggled(AssetID("a")))
        #expect(store.state.card?.keep.isEmpty == true)
    }

    @Test func emptySelectionNeverStartsDeletion() async {
        let (store, backend) = makeStore(queue: [snapshot(1)])
        await openFirstCard(store)
        let task = store.send(.commitTapped)
        #expect(task.isEmpty)
        #expect(store.state.notice == .emptySelection)
        #expect(store.state.card != nil)
        #expect(await backend.commits.isEmpty)
    }

    @Test func explicitDeleteAllCommitsAndAdvances() async {
        let (store, backend) = makeStore(queue: [snapshot(1), snapshot(2)])
        await openFirstCard(store)
        store.send(.deleteAllTapped)
        await store.finishAllEffects()
        let commits = await backend.commits
        #expect(commits == [.init(
            group: snapshot(1).id,
            decision: .delete(keep: [], delete: [AssetID("a"), AssetID("b"), AssetID("c")]),
            operation: operation(100)
        )])
        #expect(store.state.card?.snapshot == snapshot(2))
    }

    @Test func keepingEveryPhotoCompletesWithoutDeletion() async {
        let (store, backend) = makeStore(queue: [snapshot(1)])
        await openFirstCard(store)
        for name in ["a", "b", "c"] {
            store.send(.keepToggled(AssetID(name)))
        }
        store.send(.commitTapped)
        await store.finishAllEffects()
        #expect(await backend.commits.map(\.decision) == [.keepAll])
        #expect(store.state.card == nil)
    }

    @Test func selectionIsLockedWhileCommitIsPending() async {
        let (store, _) = makeStore(queue: [snapshot(1)])
        await openFirstCard(store)
        store.send(.keepToggled(AssetID("a")))
        store.send(.commitTapped)
        store.send(.keepToggled(AssetID("b")))
        #expect(store.state.card?.keep == [AssetID("a")])
        #expect(store.state.pending == .commit(operation(100)))
        await store.finishAllEffects()
    }
}

@MainActor
@Suite struct ReviewFeatureOutcomeTests {
    @Test func declinedDeletionKeepsCardAndSelection() async {
        let (store, backend) = makeStore(queue: [snapshot(1), snapshot(2)])
        await backend.setCommitOutcome(.deletionDeclined)
        await openFirstCard(store)
        store.send(.keepToggled(AssetID("a")))
        store.send(.commitTapped)
        await store.finishAllEffects()
        #expect(store.state.card?.snapshot == snapshot(1))
        #expect(store.state.card?.keep == [AssetID("a")])
        #expect(store.state.notice == .deletionDeclined)
        #expect(store.state.pending == nil)
    }

    @Test func conflictRefreshesInsteadOfSilentSuccess() async {
        let (store, backend) = makeStore(queue: [snapshot(1), snapshot(2)])
        await backend.setCommitOutcome(.conflict)
        await openFirstCard(store)
        store.send(.deleteAllTapped)
        await store.finishAllEffects()
        #expect(store.state.notice == .conflictRefreshed)
        #expect(store.state.card?.snapshot == snapshot(2))
    }

    @Test func failedCommitKeepsCard() async {
        let (store, backend) = makeStore(queue: [snapshot(1)])
        await backend.setCommitOutcome(.failed("journal"))
        await openFirstCard(store)
        store.send(.deleteAllTapped)
        await store.finishAllEffects()
        #expect(store.state.card?.snapshot == snapshot(1))
        #expect(store.state.notice == .commitFailed("journal"))
    }

    @Test func staleCommitResultIsIgnored() async {
        let (store, _) = makeStore(queue: [snapshot(1)])
        await openFirstCard(store)
        store.send(.commitFinished(operation(999), .completed))
        #expect(store.state.card?.snapshot == snapshot(1))
    }

    @Test func persistedSkipAdvances() async {
        let (store, backend) = makeStore(queue: [snapshot(1), snapshot(2)])
        await openFirstCard(store)
        store.send(.skipTapped)
        await store.finishAllEffects()
        #expect(await backend.skips == [snapshot(1).id])
        #expect(store.state.card?.snapshot == snapshot(2))
    }

    @Test func failedSkipPersistenceRetainsCard() async {
        let (store, backend) = makeStore(queue: [snapshot(1), snapshot(2)])
        await backend.setSkipOutcome(.failed("disk full"))
        await openFirstCard(store)
        store.send(.keepToggled(AssetID("b")))
        store.send(.skipTapped)
        await store.finishAllEffects()
        #expect(store.state.card == ReviewFeature.Card(snapshot: snapshot(1), keep: [AssetID("b")]))
        #expect(store.state.notice == .skipFailed("disk full"))
    }
}

@MainActor
@Suite struct ReviewFeatureRevisionTests {
    @Test func newDiscoveryRevisionRetiresOpenCard() async {
        let (store, _) = makeStore(queue: [snapshot(1), snapshot(2, discovery: 2)])
        await openFirstCard(store)
        store.send(update(.bufferReady, revision: 2))
        await store.finishAllEffects()
        #expect(store.state.card?.snapshot == snapshot(2, discovery: 2))
    }

    @Test func snapshotFromOlderRevisionIsNotOpened() {
        let (store, _) = makeStore(queue: [])
        store.send(update(.searching, revision: 2))
        store.send(.groupLoaded(snapshot(1, discovery: 1)))
        #expect(store.state.card == nil)
    }

    @Test func pendingCommitStillReconcilesAfterRevisionChange() async {
        let gate = AsyncGate()
        let backend = ReviewBackend(queue: [snapshot(1), snapshot(2, discovery: 2)])
        let client = ReviewClient(
            observeDiscovery: { AsyncStream { $0.finish() } },
            loadNextGroup: { await backend.loadNext() },
            skip: { await backend.skip($0) },
            commit: { snapshot, decision, operation in
                await gate.wait()
                return await backend.commit(snapshot, decision, operation)
            },
            makeOperationID: { operation(100) }
        )
        let store = Store(initialState: ReviewFeature.State(), reducer: ReviewFeature(client: client))
        await openFirstCard(store)
        store.send(.deleteAllTapped)
        store.send(update(.bufferReady, revision: 2))
        // The old card stays until the started deletion reports its outcome.
        #expect(store.state.card?.snapshot == snapshot(1))
        await gate.open()
        await store.finishAllEffects()
        #expect(await backend.commits.count == 1)
        #expect(store.state.card?.snapshot == snapshot(2, discovery: 2))
    }

    @Test func pendingSkipResultForRetiredCardIsIgnored() async {
        let gate = AsyncGate()
        let backend = ReviewBackend(queue: [snapshot(1), snapshot(2, discovery: 2)])
        let client = ReviewClient(
            observeDiscovery: { AsyncStream { $0.finish() } },
            loadNextGroup: { await backend.loadNext() },
            skip: { snapshot in
                await gate.wait()
                return await backend.skip(snapshot)
            },
            commit: { await backend.commit($0, $1, $2) },
            makeOperationID: { operation(100) }
        )
        let store = Store(initialState: ReviewFeature.State(), reducer: ReviewFeature(client: client))
        await openFirstCard(store)
        store.send(.skipTapped)
        store.send(update(.bufferReady, revision: 2))
        await gate.waitForWaiters(1)
        await gate.open()
        await store.finishAllEffects()
        #expect(store.state.card?.snapshot == snapshot(2, discovery: 2))
        #expect(store.state.pending == nil)
    }
}
