import Foundation
import Testing
import SweepDomain
import SweepPersistence
import SweepTestSupport
import SweepUseCases

@Suite struct ScheduledWindowTests {
    @Test func scheduledWindowRunsPassFinishesOnceAndNotifies() async throws {
        let device = try Device(photoCount: 3)
        await device.coordinator.appDidEnterBackground()
        let window = FakeExecutionWindow(kind: .scheduled)
        await device.coordinator.run(window)

        #expect(window.finishCalls == [true])
        #expect(window.hasExpirationHandler)
        #expect(try await device.vectorCount() == 3)
        #expect(await device.notifier.posted == [0])
        #expect(try await device.store.loadWorkflowState()?.notifiedPassID == device.vectorization.lastCompletedPass?.id)
        #expect(await device.coordinator.activeWindowCount == 0)
    }

    @Test func laterWindowWithoutNewWorkDoesNotNotifyAgain() async throws {
        let device = try Device(photoCount: 3)
        await device.coordinator.appDidEnterBackground()
        await device.coordinator.run(FakeExecutionWindow(kind: .scheduled))
        let second = FakeExecutionWindow(kind: .scheduled)
        await device.coordinator.run(second)
        #expect(second.finishCalls == [true])
        #expect(await device.notifier.posted.count == 1)
    }

    @Test func deniedNotificationsNeverFailVectorization() async throws {
        let device = try Device(photoCount: 3, notificationPermission: .denied)
        await device.coordinator.appDidEnterBackground()
        let window = FakeExecutionWindow(kind: .scheduled)
        await device.coordinator.run(window)
        #expect(window.finishCalls == [true])
        #expect(await device.notifier.posted.isEmpty)
        #expect(try await device.vectorCount() == 3)
    }

    @Test func manualPauseBlocksScheduledWorkAndScheduling() async throws {
        let device = try Device(photoCount: 3)
        await device.vectorization.pause()
        await device.coordinator.appDidEnterBackground()
        #expect(await device.scheduler.processingRequests == 0)

        let window = FakeExecutionWindow(kind: .scheduled)
        await device.coordinator.run(window)
        #expect(window.finishCalls == [true])
        #expect(try await device.vectorCount() == 0)
        #expect(await device.notifier.posted.isEmpty)
    }

    @Test func expirationInterruptsWithoutPausingAndReschedules() async throws {
        let embedder = GatedEmbedder(blockOnCall: 3)
        let device = try Device(photoCount: 5, embedder: embedder)
        await device.coordinator.appDidEnterBackground()
        let requestsBefore = await device.scheduler.processingRequests
        let window = FakeExecutionWindow(kind: .scheduled)
        let running = Task { await device.coordinator.run(window) }
        await embedder.gate.waitForWaiters(1)

        window.expire()
        await window.waitUntilFinished()
        await running.value
        #expect(window.finishCalls == [false])
        #expect(device.vectorization.status == .interrupted(VectorizationProgress(total: 5, vectorized: 2, deferred: 0)))
        #expect(try await device.pause == PauseState.none)
        #expect(await device.scheduler.processingRequests > requestsBefore)

        // The next granted window resumes from the checkpoint.
        let next = FakeExecutionWindow(kind: .scheduled)
        await device.coordinator.run(next)
        #expect(next.finishCalls == [true])
        #expect(try await device.vectorCount() == 5)
    }
}

@Suite struct ContinuedProcessingTests {
    @Test func userActionRequestsContinuationAndReportsProgress() async throws {
        let embedder = GatedEmbedder(blockOnCall: 3)
        let device = try Device(photoCount: 5, embedder: embedder)
        #expect(await device.coordinator.userRequestedVectorization(.userResume) == .started)
        #expect(await device.scheduler.continuedRequests == 1)

        let window = FakeExecutionWindow(kind: .continued)
        let running = Task { await device.coordinator.run(window) }
        await embedder.gate.waitForWaiters(1)
        await window.waitForProgress()
        #expect(window.reportedProgress.allSatisfy { $0.total == 5 })

        await embedder.gate.open()
        await running.value
        #expect(window.finishCalls == [true])
        #expect(try await device.vectorCount() == 5)
    }

    @Test func liveActivityCancelIsManualPauseUntilNextOpening() async throws {
        let embedder = GatedEmbedder(blockOnCall: 3)
        let device = try Device(photoCount: 5, embedder: embedder)
        await device.coordinator.userRequestedVectorization(.userResume)
        let window = FakeExecutionWindow(kind: .continued)
        let running = Task { await device.coordinator.run(window) }
        await embedder.gate.waitForWaiters(1)

        // The system reports a person's Cancel in the Live Activity as expiration.
        window.expire()
        await window.waitUntilFinished()
        await running.value
        #expect(window.finishCalls == [false])
        #expect(device.vectorization.status == .pausedByUser(VectorizationProgress(total: 5, vectorized: 2, deferred: 0)))
        #expect(try await device.pause == .manual)

        let scheduled = FakeExecutionWindow(kind: .scheduled)
        await device.coordinator.run(scheduled)
        #expect(scheduled.finishCalls == [true])
        #expect(try await device.vectorCount() == 2)

        await device.coordinator.appDidBecomeActive()
        await device.vectorization.waitUntilIdle()
        #expect(try await device.pause == PauseState.none)
        #expect(try await device.vectorCount() == 5)
    }

    @Test func noAutomaticWorkBeforeOnboardingCompletes() async throws {
        let device = try Device(photoCount: 3, automaticWorkAllowed: false)
        await device.coordinator.appDidBecomeActive()
        await device.vectorization.waitUntilIdle()
        #expect(device.vectorization.status == .idle)
        #expect(try await device.store.loadWorkflowState() == nil)

        await device.coordinator.appDidEnterBackground()
        #expect(await device.scheduler.processingRequests == 0)
        let scheduled = FakeExecutionWindow(kind: .scheduled)
        await device.coordinator.run(scheduled)
        #expect(scheduled.finishCalls == [true])
        #expect(try await device.vectorCount() == 0)

        // The person's Start still runs, with continued processing.
        await device.coordinator.appDidBecomeActive()
        #expect(await device.coordinator.userRequestedVectorization(.userResume) == .started)
        await device.vectorization.waitUntilIdle()
        #expect(try await device.vectorCount() == 3)
        #expect(await device.scheduler.continuedRequests == 1)
    }

    @Test func rejectedContinuationStillRunsInForeground() async throws {
        let device = try Device(photoCount: 3)
        await device.scheduler.setAcceptsContinuedProcessing(false)
        #expect(await device.coordinator.userRequestedVectorization(.userResume) == .started)
        await device.vectorization.waitUntilIdle()
        #expect(device.vectorization.status == .completed(deferredCount: 0))
    }
}

@Suite struct HandoffTests {
    @Test func foregroundPassContinuesInGraceWindowAndHandsBack() async throws {
        let embedder = GatedEmbedder(blockOnCall: 3)
        let device = try Device(photoCount: 5, embedder: embedder)
        await device.coordinator.appDidBecomeActive()
        await embedder.gate.waitForWaiters(1)

        await device.coordinator.appDidEnterBackground()
        let grace = try #require(await device.scheduler.graceWindows.first)
        #expect(device.discovery.current.status == .suspended)
        #expect(await device.scheduler.processingRequests == 1)

        await device.coordinator.appDidBecomeActive()
        #expect(grace.finishCalls == [true])
        await embedder.gate.open()
        await device.vectorization.waitUntilIdle()
        await device.discoverySettled()
        #expect(try await device.vectorCount() == 5)
        // Back in the foreground, discovery finds the (single) group.
        #expect(try await device.groupCount() == 1)
        #expect(grace.finishCalls == [true])
    }

    @Test func graceExpiryInterruptsWhenNothingElseKeepsThePassAlive() async throws {
        let embedder = GatedEmbedder(blockOnCall: 3)
        let device = try Device(photoCount: 5, embedder: embedder)
        await device.coordinator.appDidBecomeActive()
        await embedder.gate.waitForWaiters(1)
        await device.coordinator.appDidEnterBackground()
        let grace = try #require(await device.scheduler.graceWindows.first)

        grace.expire()
        await grace.waitUntilFinished()
        await device.vectorization.waitUntilIdle()
        #expect(grace.finishCalls == [false])
        guard case .interrupted = device.vectorization.status else {
            Issue.record("Expected interruption, got \(device.vectorization.status)")
            return
        }
        #expect(try await device.pause == PauseState.none)
    }

    @Test(.timeLimit(.minutes(1))) func repeatedRestartsKeepOneContinuedTaskAndFinishTheLibrary() async throws {
        let embedder = HoldingEmbedder()
        let device = try Device(photoCount: 5, embedder: embedder)
        #expect(await device.coordinator.userRequestedVectorization(.userResume) == .started)
        await embedder.waitForHeld()
        #expect(await device.scheduler.continuedRequests == 1)

        // Rescan tapped repeatedly while the first request's window has not arrived yet.
        for _ in 0..<3 {
            await device.coordinator.userRequestedRestart(.userResume)
            await embedder.waitForHeld()
        }
        #expect(await device.scheduler.continuedRequests == 1)

        // Once the window runs, a restart keeps it: no second request, no early finish.
        let window = FakeExecutionWindow(kind: .continued)
        let running = Task { await device.coordinator.run(window) }
        await window.waitUntilRegistered()
        await device.coordinator.userRequestedRestart(.userResume)
        await embedder.waitForHeld()
        #expect(await device.scheduler.continuedRequests == 1)
        #expect(window.finishCalls.isEmpty)
        #expect(await device.coordinator.activeWindowCount == 1)

        await embedder.release()
        await running.value
        #expect(window.finishCalls == [true])
        #expect(try await device.vectorCount() == 5)
        #expect(device.vectorization.status == .completed(deferredCount: 0))
        #expect(try await device.store.activePass() == nil)
    }

    @Test func progressCountsReusedVectorsAsDone() async throws {
        let embedder = GatedEmbedder(blockOnCall: 4)
        let device = try Device(photoCount: 3, embedder: embedder)
        await device.coordinator.userRequestedVectorization(.userResume)
        await device.vectorization.waitUntilIdle()

        await device.library.setAssets((1...5).map { index in
            PhotoAsset(
                id: "p\(index)", localIdentifier: "p\(index)",
                creationDate: Date(timeIntervalSince1970: Double(index) * 86_400),
                pixelWidth: 10, pixelHeight: 10, fileSize: nil,
                modificationDate: Date(timeIntervalSince1970: 0)
            )
        })
        await device.coordinator.userRequestedVectorization(.userResume)
        await embedder.gate.waitForWaiters(1)
        // Two new photos to analyze, three already done: the whole scope is shown.
        #expect(device.vectorization.status == .running(VectorizationProgress(total: 5, vectorized: 3, deferred: 0)))

        await embedder.gate.open()
        await device.vectorization.waitUntilIdle()
        #expect(try await device.vectorCount() == 5)
    }

    @Test(.timeLimit(.minutes(1))) func discoveryUsesVectorsCommittedDuringALongPass() async throws {
        let embedder = GatedEmbedder(blockOnCall: 7)
        let device = try Device(photoCount: 2, embedder: embedder)
        #expect(await device.coordinator.userRequestedVectorization(.userResume) == .started)
        await device.vectorization.waitUntilIdle()
        await device.discoverySettled()
        let revision = try #require(try await device.store.loadWorkflowState()).discoveryRevision
        let groupID = try #require(try await device.store.reviewQueue(for: revision).fresh.first)
        #expect(try await device.store.group(groupID)?.members.count == 2)

        // Six new photos: two batches of two commit, then the seventh embedding blocks.
        await device.library.setAssets((1...8).map { index in
            PhotoAsset(
                id: "p\(index)", localIdentifier: "p\(index)",
                creationDate: Date(timeIntervalSince1970: Double(index) * 86_400),
                pixelWidth: 10, pixelHeight: 10, fileSize: nil,
                modificationDate: Date(timeIntervalSince1970: 0)
            )
        })
        let updates = device.discovery.updates()
        #expect(await device.coordinator.userRequestedVectorization(.userResume) == .started)
        await embedder.gate.waitForWaiters(1)

        // While the pass is still blocked, discovery merges the committed vectors.
        var sawSearching = false
        for await update in updates {
            if update.status == .searching { sawSearching = true }
            guard sawSearching, update.status == .exhausted || update.status == .bufferReady else { continue }
            if let members = try await device.store.group(groupID)?.members, members.count > 2 { break }
        }
        #expect(device.vectorization.status != .completed(deferredCount: 0))
        #expect(try await device.store.group(groupID)?.members.count == 6)

        await embedder.gate.open()
        await device.vectorization.waitUntilIdle()
        await device.discovery.waitUntilIdle()
        #expect(try await device.store.group(groupID)?.members.count == 8)
    }

    @Test func discoveryNeverRunsInTheBackground() async throws {
        let device = try Device(photoCount: 3)
        await device.coordinator.appDidEnterBackground()
        await device.coordinator.run(FakeExecutionWindow(kind: .scheduled))
        await device.discovery.waitUntilIdle()
        #expect(try await device.store.loadWorkflowState()?.gate.isOpen == true)
        #expect(try await device.groupCount() == 0)

        await device.coordinator.appDidBecomeActive()
        await device.discoverySettled()
        #expect(try await device.groupCount() == 1)
    }
}

@Suite struct OverlappingWindowTests {
    @Test func overlappingWindowsShareOnePassAndEachFinishesOnce() async throws {
        let embedder = GatedEmbedder(blockOnCall: 3)
        let device = try Device(photoCount: 5, embedder: embedder)
        await device.coordinator.appDidEnterBackground()
        let first = FakeExecutionWindow(kind: .scheduled)
        let second = FakeExecutionWindow(kind: .scheduled)
        let runningFirst = Task { await device.coordinator.run(first) }
        await embedder.gate.waitForWaiters(1)
        let runningSecond = Task { await device.coordinator.run(second) }
        await second.waitUntilRegistered()

        await embedder.gate.open()
        await runningFirst.value
        await runningSecond.value
        #expect(first.finishCalls == [true])
        #expect(second.finishCalls == [true])
        #expect(await embedder.calls == 5)
        #expect(try await device.vectorCount() == 5)
        // The queued follow-up pass had no work; the real pass is still announced, once.
        let posted = await device.notifier.posted
        #expect(posted == [0], "posted: \(posted)")
    }

    @Test func expiringOneWindowKeepsThePassRunningForTheOther() async throws {
        let embedder = GatedEmbedder(blockOnCall: 3)
        let device = try Device(photoCount: 5, embedder: embedder)
        await device.coordinator.appDidEnterBackground()
        let first = FakeExecutionWindow(kind: .scheduled)
        let second = FakeExecutionWindow(kind: .scheduled)
        let runningFirst = Task { await device.coordinator.run(first) }
        await embedder.gate.waitForWaiters(1)
        let runningSecond = Task { await device.coordinator.run(second) }
        await second.waitUntilRegistered()

        first.expire()
        await first.waitUntilFinished()
        #expect(first.finishCalls == [false])
        await embedder.gate.open()
        await runningFirst.value
        await runningSecond.value
        #expect(second.finishCalls == [true])
        #expect(try await device.vectorCount() == 5)
    }
}
