import Foundation
import Testing
import SweepDomain
import SweepPersistence
import SweepTestSupport

@Suite struct WorkflowStatePersistenceTests {
    @Test func absentBeforeFirstSave() async throws {
        #expect(try await TemporaryStore().open().loadWorkflowState() == nil)
    }

    @Test(arguments: [
        InitialPassGate.State.awaitingInitialPass(nil),
        .awaitingInitialPass(passID(7)),
        .open(deferredCount: 3),
    ])
    func roundTripsAcrossReopen(gate: InitialPassGate.State) async throws {
        let file = try TemporaryStore()
        var state = try workflow(revision: 4, generation: 2, paused: true)
        state.gate = InitialPassGate(state: gate)
        try await file.open().saveWorkflowState(state)
        #expect(try await file.open().loadWorkflowState() == state)
    }

    @Test func manualPauseSurvivesRelaunch() async throws {
        let file = try TemporaryStore()
        try await file.open().saveWorkflowState(try workflow(paused: true))
        let restored = try #require(try await file.open().loadWorkflowState())
        #expect(PausePolicy.decide(.backgroundScheduled, current: restored.pause) == .blockedByManualPause)
    }
}

@Suite struct VectorizationPassPersistenceTests {
    @Test func checkpointedPassResumesWithOutcomes() async throws {
        let file = try TemporaryStore()
        let store = try file.open()
        _ = try await store.register([discovered("a"), discovered("b"), discovered("c")])
        let pass = VectorizationPass(id: passID(1), kind: .initial, scope: scope, workSet: [AssetID("a"), AssetID("b"), AssetID("c")])
        try await store.beginPass(pass)
        try await store.recordDeferred([AssetID("b"): .unavailable("iCloud")], pass: pass.id)

        let restored = try #require(try await file.open().activePass())
        #expect(restored.id == pass.id)
        #expect(restored.kind == .initial)
        #expect(restored.scope == scope)
        #expect(restored.outcomes[AssetID("b")] == .deferred(.unavailable("iCloud")))
        #expect(restored.pendingAssets == [AssetID("a"), AssetID("c")])
        #expect(try await file.open().assets([AssetID("b")])[AssetID("b")]?.state == .deferred(.unavailable("iCloud")))
    }

    @Test func checkpointNeverMarksUncommittedWorkDone() async throws {
        let file = try TemporaryStore()
        let store = try file.open()
        let records = try await store.register([discovered("a")])
        try await store.beginPass(VectorizationPass(id: passID(1), kind: .initial, scope: scope, workSet: [AssetID("a")]))
        // Intent recorded but never committed: the pass must still list the asset as pending.
        try await store.beginVectorWrite(operation(1), intents: records.map(intent(for:)))
        #expect(try await file.open().activePass()?.pendingAssets == [AssetID("a")])
    }

    @Test func newPassSupersedesAndFinishClears() async throws {
        let store = try TemporaryStore().open()
        try await store.beginPass(VectorizationPass(id: passID(1), kind: .initial, scope: scope, workSet: [AssetID("a")]))
        try await store.beginPass(VectorizationPass(id: passID(2), kind: .incremental, scope: scope, workSet: [AssetID("b")]))
        #expect(try await store.activePass()?.id == passID(2))
        try await store.finishPass(passID(1))
        #expect(try await store.activePass()?.id == passID(2))
        try await store.finishPass(passID(2))
        #expect(try await store.activePass() == nil)
    }
}

@Suite struct DiscoveryProgressPersistenceTests {
    func expansion(_ chain: [String]) throws -> ComponentExpansion {
        var expansion = try #require(ComponentExpansion(
            seed: AssetID(chain[0]), seedCreationDate: Date(timeIntervalSince1970: 86_400),
            scope: scope, threshold: try threshold(0.9), generation: generation
        ))
        for (query, next) in zip(chain, chain.dropFirst()) {
            try expansion.absorb([Neighbor(asset: AssetID(next), creationDate: Date(timeIntervalSince1970: 86_400), score: 0.95)], for: AssetID(query), isLastPage: true)
        }
        return expansion
    }

    @Test func interruptedExpansionResumesAfterRelaunch() async throws {
        let file = try TemporaryStore()
        let partial = try expansion(["a", "b", "c"])
        let progress = DiscoveryProgress(revision: DiscoveryRevision(1), seedCursor: AssetID("0"), expansion: partial.snapshot)
        try await file.open().saveDiscoveryProgress(progress)

        let restored = try #require(try await file.open().discoveryProgress(for: DiscoveryRevision(1)))
        #expect(restored == progress)
        let snapshot = try #require(restored.expansion)
        let resumed = try #require(ComponentExpansion(restoring: snapshot))
        #expect(resumed.nextQuery == AssetID("c"))
        #expect(resumed.members == [AssetID("a"), AssetID("b"), AssetID("c")])
    }

    @Test func growingFrontierIsAppendedAndReplacedExpansionIsRewritten() async throws {
        let file = try TemporaryStore()
        let store = try file.open()
        let revision = DiscoveryRevision(1)
        try await store.saveDiscoveryProgress(DiscoveryProgress(revision: revision, expansion: try expansion(["a", "b"]).snapshot))
        try await store.saveDiscoveryProgress(DiscoveryProgress(revision: revision, expansion: try expansion(["a", "b", "c", "d"]).snapshot))
        #expect(try await file.open().discoveryProgress(for: revision)?.expansion?.visited.map(\.rawValue) == ["a", "b", "c", "d"])

        try await store.saveDiscoveryProgress(DiscoveryProgress(revision: revision, expansion: try expansion(["x", "y"]).snapshot))
        #expect(try await file.open().discoveryProgress(for: revision)?.expansion?.visited.map(\.rawValue) == ["x", "y"])

        try await store.saveDiscoveryProgress(DiscoveryProgress(revision: revision, seedCursor: AssetID("y"), isSeedCursorExhausted: true))
        let finished = try #require(try await file.open().discoveryProgress(for: revision))
        #expect(finished.expansion == nil)
        #expect(finished.isSeedCursorExhausted)
    }

    @Test func restoringRejectsInconsistentSnapshots() throws {
        let duplicate = ComponentExpansion.Snapshot(
            seed: AssetID("a"), scope: scope, threshold: try threshold(0.9), generation: generation,
            visited: [AssetID("a"), AssetID("a")], queriedCount: 0
        )
        #expect(ComponentExpansion(restoring: duplicate) == nil)
        let wrongSeed = ComponentExpansion.Snapshot(
            seed: AssetID("a"), scope: scope, threshold: try threshold(0.9), generation: generation,
            visited: [AssetID("b")], queriedCount: 0
        )
        #expect(ComponentExpansion(restoring: wrongSeed) == nil)
    }
}
