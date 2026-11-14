import CoreGraphics
import Foundation
import Testing
import SweepDomain
import SweepPersistence
import SweepTestSupport
import SweepUseCases

private let threePhotos = [photo("a"), photo("b"), photo("c")]
private let fivePhotos = (1...5).map { photo("p\($0)") }

@Suite struct InitialPassAndReuseTests {
    @Test func initialPassVectorizesFromThumbnailsAndOpensGate() async throws {
        let harness = try Harness(photos: threePhotos)
        let embedder = FakeEmbeddingProvider()
        let (executor, store) = try harness.launch(embedder: embedder)

        #expect(await harness.run(executor) == .started)
        #expect(executor.status == .completed(deferredCount: 0))
        #expect(try await harness.vectors().count() == 3)
        #expect(try await store.loadWorkflowState()?.gate.state == .open(deferredCount: 0))
        #expect(try await store.statistics().vectorizedPhotos == 3)
        // Processing never needs full resolution.
        #expect(await harness.library.fullResolutionRequestCount == 0)
        #expect(await harness.library.imageRequests.first == .thumbnail(assetID: "a", size: CGSize(width: 224, height: 224)))
    }

    @Test func gateStaysClosedWhileInitialPassIsIncomplete() async throws {
        let harness = try Harness(photos: fivePhotos)
        let embedder = GatedEmbedder(blockOnCall: 3)
        let (executor, store) = try harness.launch(embedder: embedder)
        await executor.handle(.appActivation)
        await embedder.gate.waitForWaiters(1)
        #expect(try await !(store.loadWorkflowState()?.gate.isOpen ?? true))
        await embedder.gate.open()
        await executor.waitUntilIdle()
        #expect(try await store.loadWorkflowState()?.gate.isOpen == true)
    }

    @Test func relaunchReusesCompatibleVectors() async throws {
        let harness = try Harness(photos: threePhotos)
        let embedder = FakeEmbeddingProvider()
        await harness.run(try harness.launch(embedder: embedder).0)
        #expect(await embedder.embedCount == 3)

        let (relaunched, store) = try harness.launch(embedder: embedder)
        await harness.run(relaunched)
        #expect(await embedder.embedCount == 3)
        #expect(relaunched.status == .completed(deferredCount: 0))
        #expect(try await store.loadWorkflowState()?.gate.isOpen == true)
    }

    @Test func editedPhotoIsVectorizedAgain() async throws {
        let harness = try Harness(photos: threePhotos)
        let embedder = FakeEmbeddingProvider()
        await harness.run(try harness.launch(embedder: embedder).0)
        await harness.library.setAssets([photo("a", modified: 99), photo("b"), photo("c")])

        await harness.run(try harness.launch(embedder: embedder).0, .automaticForeground)
        #expect(await embedder.embedCount == 4)
    }

    @Test func modelChangeStartsNewGenerationAndRebuildsIndex() async throws {
        let harness = try Harness(photos: threePhotos)
        let embedder = FakeEmbeddingProvider()
        await harness.run(try harness.launch(embedder: embedder).0)

        await embedder.changeModel(revision: 2, defaultVector: [0, 1, 0, 0])
        let (executor, store) = try harness.launch(embedder: embedder)
        await harness.run(executor)

        let state = try #require(try await store.loadWorkflowState())
        #expect(state.indexGeneration == IndexGeneration(2))
        #expect(state.indexCompatibility?.dimensions == 4)
        #expect(state.gate.isOpen)
        #expect(await embedder.embedCount == 6)
        #expect(try await harness.vectors(generation: 2, dimensions: 4).count() == 3)
        #expect(await harness.vectorStores.stores[1] == nil)
    }
}

@Suite struct AutomaticTriggerTests {
    @Test func libraryChangesTriggerIncrementalPassWithoutClosingGate() async throws {
        let harness = try Harness(photos: threePhotos)
        let embedder = FakeEmbeddingProvider()
        let (executor, store) = try harness.launch(embedder: embedder)
        await harness.run(executor)

        let changes = FakePhotoLibraryChanges()
        await executor.startObservingLibraryChanges(changes)
        #expect(changes.observerCount == 1)
        await harness.library.setAssets(threePhotos + [photo("d")])
        let fetchesBefore = await harness.library.fetchCount
        changes.send()

        // The triggered pass is running once it fetches the library; then wait for it to end.
        await harness.library.waitForFetches(fetchesBefore + 1)
        await executor.waitUntilIdle()
        #expect(try await harness.vectors().count() == 4)
        #expect(try await store.loadWorkflowState()?.gate.isOpen == true)
        #expect(await embedder.embedCount == 4)
        await executor.stopObservingLibraryChanges()
    }

    @Test func triggerDuringPassQueuesFollowUpPass() async throws {
        let harness = try Harness(photos: fivePhotos)
        let embedder = GatedEmbedder(blockOnCall: 3)
        let (executor, _) = try harness.launch(embedder: embedder)
        #expect(await executor.handle(.appActivation) == .started)
        await embedder.gate.waitForWaiters(1)

        await harness.library.setAssets(fivePhotos + [photo("new")])
        #expect(await executor.handle(.automaticForeground) == .queued)
        await embedder.gate.open()
        await executor.waitUntilIdle()
        #expect(try await harness.vectors().count() == 6)
    }

    @Test func observerCancellationDoesNotStopVectorization() async throws {
        let harness = try Harness(photos: fivePhotos)
        let embedder = GatedEmbedder(blockOnCall: 3)
        let (executor, _) = try harness.launch(embedder: embedder)
        let observer = Task {
            for await _ in executor.statusUpdates() {}
        }
        await executor.handle(.appActivation)
        await embedder.gate.waitForWaiters(1)
        observer.cancel()
        await embedder.gate.open()
        await executor.waitUntilIdle()
        #expect(executor.status == .completed(deferredCount: 0))
    }
}

@Suite struct PauseResumeRetryTests {
    /// Starts a pass and pauses it during the second batch.
    func pausedMidPass(_ harness: Harness) async throws -> (VectorizationExecutor, SwiftDataMetadataStore, GatedEmbedder) {
        let embedder = GatedEmbedder(blockOnCall: 3)
        let (executor, store) = try harness.launch(embedder: embedder)
        await executor.handle(.appActivation)
        await embedder.gate.waitForWaiters(1)
        await executor.pause()
        return (executor, store, embedder)
    }

    @Test func pauseCheckpointsAndBlocksAutomaticAndBackgroundWork() async throws {
        let harness = try Harness(photos: fivePhotos)
        let (executor, store, _) = try await pausedMidPass(harness)

        #expect(executor.status == .pausedByUser(VectorizationProgress(total: 5, vectorized: 2, deferred: 0)))
        #expect(try await harness.vectors().count() == 2)
        #expect(try await store.loadWorkflowState()?.pause == .manual)
        for trigger in [VectorizationTrigger.automaticForeground, .backgroundContinuation, .backgroundScheduled] {
            #expect(await executor.handle(trigger) == .blockedByManualPause)
        }
        await executor.waitUntilIdle()
        #expect(try await harness.vectors().count() == 2)
    }

    @Test func pauseSurvivesRelaunchUntilAppOpening() async throws {
        let harness = try Harness(photos: fivePhotos)
        _ = try await pausedMidPass(harness)

        let (relaunched, store) = try harness.launch(embedder: FakeEmbeddingProvider())
        #expect(await relaunched.handle(.backgroundScheduled) == .blockedByManualPause)
        #expect(await harness.run(relaunched, .appActivation) == .started)
        #expect(relaunched.status == .completed(deferredCount: 0))
        #expect(try await store.loadWorkflowState()?.pause == PauseState.none)
        #expect(try await harness.vectors().count() == 5)
    }

    @Test func resumeContinuesFromCheckpoint() async throws {
        let harness = try Harness(photos: fivePhotos)
        let (executor, _, embedder) = try await pausedMidPass(harness)
        let callsBeforeResume = await embedder.calls
        await executor.resume()
        await executor.waitUntilIdle()
        #expect(executor.status == .completed(deferredCount: 0))
        // Only the unfinished photos are embedded again: the interrupted one and the rest.
        #expect(await embedder.calls == callsBeforeResume + 3)
    }

    @Test func systemInterruptionIsNotAManualPause() async throws {
        let harness = try Harness(photos: fivePhotos)
        let embedder = GatedEmbedder(blockOnCall: 3)
        let (executor, store) = try harness.launch(embedder: embedder)
        await executor.handle(.appActivation)
        await embedder.gate.waitForWaiters(1)
        await executor.interrupt()

        #expect(executor.status == .interrupted(VectorizationProgress(total: 5, vectorized: 2, deferred: 0)))
        #expect(try await store.loadWorkflowState()?.pause == PauseState.none)
        #expect(await harness.run(executor, .backgroundContinuation) == .started)
        #expect(executor.status == .completed(deferredCount: 0))
    }

    @Test func relaunchAfterInterruptionResumesSamePass() async throws {
        let harness = try Harness(photos: fivePhotos)
        let embedder = GatedEmbedder(blockOnCall: 3)
        let (executor, store) = try harness.launch(embedder: embedder)
        await executor.handle(.appActivation)
        await embedder.gate.waitForWaiters(1)
        await executor.interrupt()
        let interruptedPass = try #require(try await store.activePass())

        let second = FakeEmbeddingProvider()
        let (relaunched, relaunchedStore) = try harness.launch(embedder: second)
        await harness.run(relaunched)
        #expect(await second.embedCount == 3)
        #expect(try await relaunchedStore.activePass() == nil)
        #expect(interruptedPass.kind == .initial)
        #expect(try await relaunchedStore.loadWorkflowState()?.gate.isOpen == true)
    }

    @Test func systemicFailureStopsPassThenRetrySucceeds() async throws {
        let harness = try Harness(photos: threePhotos)
        let (executor, store) = try harness.launch(embedder: FakeEmbeddingProvider())
        try await harness.vectors().setFailure(.vectorStore("disk full"))

        await harness.run(executor)
        guard case .failed(.systemic, _) = executor.status else {
            Issue.record("Expected a systemic failure, got \(executor.status)")
            return
        }
        #expect(try await !(store.loadWorkflowState()?.gate.isOpen ?? true))
        #expect(try await store.statistics().unavailablePhotos == 0)
        #expect(await harness.sleeper.sleeps.count == 2)

        try await harness.vectors().setFailure(nil)
        await executor.retry()
        await executor.waitUntilIdle()
        #expect(executor.status == .completed(deferredCount: 0))
    }

    @Test func retryIsIgnoredUnlessFailedOrInterrupted() async throws {
        let harness = try Harness(photos: threePhotos)
        let embedder = FakeEmbeddingProvider()
        let (executor, _) = try harness.launch(embedder: embedder)
        await executor.retry()
        await executor.waitUntilIdle()
        #expect(executor.status == .idle)
        #expect(await embedder.embedCount == 0)
    }
}

@Suite struct DeferralAndAuthorizationTests {
    @Test func unavailablePhotoIsDeferredAfterRetriesAndReviewCanStart() async throws {
        let harness = try Harness(photos: threePhotos)
        await harness.library.setUnavailable(["b"])
        let (executor, store) = try harness.launch(embedder: FakeEmbeddingProvider())

        await harness.run(executor)
        #expect(executor.status == .completed(deferredCount: 1))
        #expect(try await store.loadWorkflowState()?.gate.state == .open(deferredCount: 1))
        #expect(try await store.statistics().unavailablePhotos == 1)
        #expect(await harness.sleeper.sleeps == [.seconds(1), .seconds(2)])
    }

    @Test func manyFailuresInARowStopInsteadOfDeferringEverything() async throws {
        let harness = try Harness(photos: fivePhotos)
        await harness.library.setUnavailable(Set(fivePhotos.map(\.id)))
        let configuration = VectorizationConfiguration(batchSize: 2, maxConsecutiveDeferrals: 3)
        let (executor, store) = try harness.launch(embedder: FakeEmbeddingProvider(), configuration: configuration)

        await harness.run(executor)
        guard case .failed(.systemic, _) = executor.status else {
            Issue.record("Expected the deferral breaker to stop the pass, got \(executor.status)")
            return
        }
        #expect(try await store.statistics().unavailablePhotos == 3)
        #expect(try await !(store.loadWorkflowState()?.gate.isOpen ?? true))
    }

    @Test func deniedAccessStopsWithoutMarkingPhotosUnavailable() async throws {
        let harness = try Harness(photos: threePhotos)
        await harness.library.setAuthorizationError(.authorization("denied"))
        let (executor, store) = try harness.launch(embedder: FakeEmbeddingProvider())

        await harness.run(executor)
        #expect(executor.status == .failed(.authorization, VectorizationProgress(total: 0, vectorized: 0, deferred: 0)))
        #expect(try await store.statistics().unavailablePhotos == 0)
    }

    @Test func photoRemovedFromLibraryDuringPassIsDeferredNotFatal() async throws {
        let harness = try Harness(photos: fivePhotos)
        let embedder = GatedEmbedder(blockOnCall: 3)
        let (executor, _) = try harness.launch(embedder: embedder)
        await executor.handle(.appActivation)
        await embedder.gate.waitForWaiters(1)
        await executor.interrupt()

        // p5 disappears before the pass resumes.
        await harness.library.setAssets(Array(fivePhotos.prefix(4)))
        let (relaunched, _) = try harness.launch(embedder: FakeEmbeddingProvider())
        await harness.run(relaunched)
        #expect(relaunched.status == .completed(deferredCount: 1))
    }
}
