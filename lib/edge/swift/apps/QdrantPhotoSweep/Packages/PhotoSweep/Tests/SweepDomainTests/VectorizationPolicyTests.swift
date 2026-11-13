import Foundation
import Testing
import SweepDomain

@Suite struct DateScopeTests {
    @Test func boundsAreInclusive() {
        #expect(januaryScope.contains(date(0)))
        #expect(januaryScope.contains(date(30)))
        #expect(januaryScope.contains(date(15)))
    }

    @Test func datesOutsideAndMissingDatesAreExcluded() {
        #expect(!januaryScope.contains(date(0).addingTimeInterval(-1)))
        #expect(!januaryScope.contains(date(30).addingTimeInterval(1)))
        #expect(!januaryScope.contains(nil))
    }
}

@Suite struct VectorReusePolicyTests {
    let compatibility = EmbeddingCompatibility(model: "featurePrint", modelRevision: 2, preprocessing: "thumb-224", dimensions: 768)
    let revision = AssetContentRevision("2026-01-01T00:00:00Z")
    let generation = IndexGeneration(1)

    func stored(
        revision: AssetContentRevision? = nil,
        compatibility: EmbeddingCompatibility? = nil,
        generation: IndexGeneration? = nil,
        isCommitted: Bool = true
    ) -> StoredVector {
        StoredVector(
            assetID: asset("a"),
            contentRevision: revision ?? self.revision,
            compatibility: compatibility ?? self.compatibility,
            generation: generation ?? self.generation,
            isCommitted: isCommitted
        )
    }

    func decide(_ existing: StoredVector?) -> VectorReuseDecision {
        VectorReusePolicy.decide(existing: existing, currentRevision: revision, compatibility: compatibility, generation: generation)
    }

    @Test func reusesCommittedCompatibleUnchangedVector() {
        #expect(decide(stored()) == .reuse)
    }

    @Test func missingVectorIsVectorized() {
        #expect(decide(nil) == .revectorize(.missing))
    }

    @Test func pointWithoutMetadataCommitIsNotSuccess() {
        #expect(decide(stored(isCommitted: false)) == .revectorize(.uncommitted))
    }

    @Test func editedAssetIsVectorizedAgain() {
        #expect(decide(stored(revision: AssetContentRevision("edited"))) == .revectorize(.contentChanged))
    }

    @Test func sameDimensionsWithDifferentModelRevisionIsIncompatible() {
        let older = EmbeddingCompatibility(model: "featurePrint", modelRevision: 1, preprocessing: "thumb-224", dimensions: 768)
        #expect(decide(stored(compatibility: older)) == .revectorize(.incompatible))
    }

    @Test func differentPreprocessingIsIncompatible() {
        let other = EmbeddingCompatibility(model: "featurePrint", modelRevision: 2, preprocessing: "thumb-512", dimensions: 768)
        #expect(decide(stored(compatibility: other)) == .revectorize(.incompatible))
    }

    @Test func vectorFromOldGenerationIsNotReused() {
        #expect(decide(stored(generation: IndexGeneration(0))) == .revectorize(.staleGeneration))
    }
}

@Suite struct RetryPolicyTests {
    let policy = RetryPolicy(maxAssetAttempts: 3, maxSystemicAttempts: 2, baseDelay: .seconds(1), maxDelay: .seconds(5))

    @Test func unavailableAssetRetriesThenDefers() {
        let failure = VectorizationFailure.assetUnavailable("iCloud")
        #expect(policy.decide(failure, attempt: 1) == .retry(after: .seconds(1)))
        #expect(policy.decide(failure, attempt: 2) == .retry(after: .seconds(2)))
        #expect(policy.decide(failure, attempt: 3) == .deferAsset(.unavailable("iCloud")))
    }

    @Test(arguments: [VectorizationFailure.transient("busy"), .systemic("busy")])
    func infrastructureFailureStopsPassInsteadOfDeferring(failure: VectorizationFailure) {
        #expect(policy.decide(failure, attempt: 1) == .retry(after: .seconds(1)))
        #expect(policy.decide(failure, attempt: 2) == .stopPass(.systemic("busy")))
    }

    @Test func authorizationAndIncompatibilityStopImmediately() {
        #expect(policy.decide(.authorization, attempt: 1) == .stopPass(.authorization))
        #expect(policy.decide(.incompatibleEmbedding("dims"), attempt: 1) == .stopPass(.incompatibleEmbedding("dims")))
    }

    @Test func backoffDoublesAndIsCapped() {
        #expect(policy.delay(afterAttempt: 1) == .seconds(1))
        #expect(policy.delay(afterAttempt: 2) == .seconds(2))
        #expect(policy.delay(afterAttempt: 3) == .seconds(4))
        #expect(policy.delay(afterAttempt: 4) == .seconds(5))
        #expect(policy.delay(afterAttempt: 60) == .seconds(5))
    }

    @Test func singleAttemptPolicyNeverRetries() {
        let strict = RetryPolicy(maxAssetAttempts: 1, maxSystemicAttempts: 1, baseDelay: .zero, maxDelay: .zero)
        #expect(strict.decide(.assetUnavailable("x"), attempt: 1) == .deferAsset(.unavailable("x")))
        #expect(strict.decide(.systemic("x"), attempt: 1) == .stopPass(.systemic("x")))
    }
}

@Suite struct VectorizationPassTests {
    @Test func emptyLibraryCompletesImmediately() {
        let pass = VectorizationPass(id: passID(1), kind: .initial, scope: januaryScope, workSet: [])
        #expect(pass.isComplete)
        #expect(pass.progress == VectorizationProgress(total: 0, vectorized: 0, deferred: 0))
    }

    @Test func deferredAssetsCountTowardCompletion() {
        var pass = VectorizationPass(id: passID(1), kind: .initial, scope: januaryScope, workSet: [asset("a"), asset("b")])
        pass.record(.vectorized, for: asset("a"))
        #expect(!pass.isComplete)
        pass.record(.deferred(.unavailable("iCloud")), for: asset("b"))
        #expect(pass.isComplete)
        #expect(pass.progress == VectorizationProgress(total: 2, vectorized: 1, deferred: 1))
    }

    @Test func finalBatchCompletesPass() {
        let work = (0..<5).map { asset("p\($0)") }
        var pass = VectorizationPass(id: passID(1), kind: .initial, scope: januaryScope, workSet: work)
        for item in work.prefix(4) {
            pass.record(.vectorized, for: item)
        }
        #expect(pass.pendingAssets == [asset("p4")])
        pass.record(.vectorized, for: asset("p4"))
        #expect(pass.isComplete)
        #expect(pass.progress.remaining == 0)
    }

    @Test func laterArrivalsAreNotPartOfCapturedWorkSet() {
        var pass = VectorizationPass(id: passID(1), kind: .initial, scope: januaryScope, workSet: [asset("a")])
        let recorded = pass.record(.vectorized, for: asset("new"))
        #expect(!recorded)
        #expect(pass.progress.total == 1)
    }

    @Test func duplicateWorkSetEntriesAreCountedOnce() {
        let pass = VectorizationPass(id: passID(1), kind: .initial, scope: januaryScope, workSet: [asset("a"), asset("a")])
        #expect(pass.progress.total == 1)
    }
}

@Suite struct InitialPassGateTests {
    func completedPass(_ id: UInt64, kind: VectorizationPass.Kind, deferred: Bool = false) -> VectorizationPass {
        var pass = VectorizationPass(id: passID(id), kind: kind, scope: januaryScope, workSet: [asset("a"), asset("b")])
        pass.record(.vectorized, for: asset("a"))
        pass.record(deferred ? .deferred(.unavailable("x")) : .vectorized, for: asset("b"))
        return pass
    }

    @Test func blocksReviewUntilInitialPassCompletes() {
        var gate = InitialPassGate()
        gate.beginInitialPass(passID(1))
        var pass = VectorizationPass(id: passID(1), kind: .initial, scope: januaryScope, workSet: [asset("a"), asset("b")])
        pass.record(.vectorized, for: asset("a"))
        gate.passFinished(pass)
        #expect(!gate.isOpen)
    }

    @Test func opensWithDeferredCountVisible() {
        var gate = InitialPassGate()
        gate.beginInitialPass(passID(1))
        gate.passFinished(completedPass(1, kind: .initial, deferred: true))
        #expect(gate.state == .open(deferredCount: 1))
    }

    @Test func incrementalPassNeitherOpensNorClosesGate() {
        var gate = InitialPassGate()
        gate.beginInitialPass(passID(1))
        gate.passFinished(completedPass(2, kind: .incremental))
        #expect(!gate.isOpen)

        gate.passFinished(completedPass(1, kind: .initial))
        gate.passFinished(completedPass(3, kind: .incremental))
        #expect(gate.state == .open(deferredCount: 0))
    }

    @Test func obsoleteInitialPassDoesNotOpenGate() {
        var gate = InitialPassGate()
        gate.beginInitialPass(passID(1))
        gate.beginInitialPass(passID(2))
        gate.passFinished(completedPass(1, kind: .initial))
        #expect(!gate.isOpen)
    }

    @Test func scopeChangeOrRescanClosesOpenGate() {
        var gate = InitialPassGate()
        gate.beginInitialPass(passID(1))
        gate.passFinished(completedPass(1, kind: .initial))
        gate.beginInitialPass(passID(2))
        #expect(gate.state == .awaitingInitialPass(passID(2)))
    }
}

@Suite struct PausePolicyTests {
    @Test(arguments: [VectorizationTrigger.automaticForeground, .backgroundContinuation, .backgroundScheduled])
    func manualPauseBlocksAutomaticAndBackgroundWork(trigger: VectorizationTrigger) {
        #expect(PausePolicy.decide(trigger, current: .manual) == .blockedByManualPause)
        #expect(PausePolicy.decide(trigger, current: .none) == .run(pause: .none))
    }

    @Test(arguments: [VectorizationTrigger.appActivation, .userResume, .userRetry])
    func activationAndExplicitUserActionClearManualPause(trigger: VectorizationTrigger) {
        #expect(PausePolicy.decide(trigger, current: .manual) == .run(pause: .none))
    }
}
