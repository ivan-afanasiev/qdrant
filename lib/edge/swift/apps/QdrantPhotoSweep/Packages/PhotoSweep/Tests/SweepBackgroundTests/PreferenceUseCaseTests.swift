import Foundation
import Testing
import SweepDomain
import SweepTestSupport
import SweepUseCases

private actor Counter {
    private(set) var value = 0

    func increment() {
        value += 1
    }
}

@Suite struct PreferenceUseCaseTests {
    let now = Date(timeIntervalSince1970: 1_790_000_000)

    @Test func defaultsBeforeFirstSave() async throws {
        let device = try Device(photoCount: 1)
        #expect(try await LoadPreferences(workflow: device.store).execute() == .defaults)
    }

    @Test func completingOnboardingSavesChoicesAndStartsFirstPassAsUserAction() async throws {
        let device = try Device(photoCount: 3)
        let observed = Counter()
        let complete = CompleteOnboarding(workflow: device.store, lifecycle: device.coordinator, observeLibrary: { await observed.increment() }, now: { now })
        try await complete.execute(datePreset: .lastMonth)
        await device.vectorization.waitUntilIdle()

        let preferences = try await LoadPreferences(workflow: device.store).execute()
        #expect(preferences == Preferences(datePreset: .lastMonth, similarity: .balanced, isOnboardingCompleted: true))
        #expect(await observed.value == 1)
        #expect(await device.scheduler.continuedRequests == 1)
        #expect(device.vectorization.status == .completed(deferredCount: 0))
    }

    @Test func dateRangeChangeStartsScopedPassAndNewDiscoveryRevision() async throws {
        let device = try Device(photoCount: 3)
        try await CompleteOnboarding(workflow: device.store, lifecycle: device.coordinator, observeLibrary: {}, now: { now }).execute(datePreset: .allTime)
        await device.vectorization.waitUntilIdle()
        let before = try #require(try await device.store.loadWorkflowState())
        #expect(before.gate.isOpen)

        try await UpdateDateScope(workflow: device.store, discovery: device.discovery, lifecycle: device.coordinator, now: { now }).execute(.lastWeek)
        await device.vectorization.waitUntilIdle()
        let after = try #require(try await device.store.loadWorkflowState())
        #expect(after.datePreset == .lastWeek)
        #expect(after.discoveryRevision == before.discoveryRevision.next())
        // The scoped initial pass ran again and reopened review for the new range.
        #expect(after.gate.isOpen)
        #expect(after.scope.end == .distantFuture)
        #expect(after.scope.start > Date(timeIntervalSince1970: 1_700_000_000))
        #expect(await device.scheduler.continuedRequests == 2)
    }

    @Test func thresholdChangeReusesVectorsAndStartsNewRevision() async throws {
        let embedder = FakeEmbeddingProvider()
        let device = try Device(photoCount: 3, embedder: embedder)
        try await CompleteOnboarding(workflow: device.store, lifecycle: device.coordinator, observeLibrary: {}, now: { now }).execute(datePreset: .allTime)
        await device.vectorization.waitUntilIdle()
        let embeddedBefore = await embedder.embedCount
        let revisionBefore = try #require(try await device.store.loadWorkflowState()).discoveryRevision

        try await UpdateSimilarityThreshold(workflow: device.store, discovery: device.discovery).execute(.strict)
        let state = try #require(try await device.store.loadWorkflowState())
        #expect(SimilarityPreset(threshold: state.threshold) == .strict)
        #expect(state.discoveryRevision == revisionBefore.next())
        #expect(state.gate.isOpen)
        #expect(await embedder.embedCount == embeddedBefore)
    }

    @Test func rescanReusesVectorsAndReopensReviewAfterPass() async throws {
        let embedder = FakeEmbeddingProvider()
        let device = try Device(photoCount: 3, embedder: embedder)
        try await CompleteOnboarding(workflow: device.store, lifecycle: device.coordinator, observeLibrary: {}, now: { now }).execute(datePreset: .allTime)
        await device.vectorization.waitUntilIdle()
        let embeddedBefore = await embedder.embedCount

        try await RescanLibrary(workflow: device.store, discovery: device.discovery, lifecycle: device.coordinator).execute()
        await device.vectorization.waitUntilIdle()
        #expect(await embedder.embedCount == embeddedBefore)
        #expect(try await device.store.loadWorkflowState()?.gate.isOpen == true)
    }

    @Test func presetsResolveToRollingOpenEndedRanges() {
        let range = DateScopePreset.lastMonth.range(endingAt: now)
        #expect(range.end == .distantFuture)
        #expect(range.start < now)
        #expect(range.start > now.addingTimeInterval(-32 * 86_400))
        #expect(DateScopePreset.allTime.range(endingAt: now) == DateRange(start: .distantPast, end: .distantFuture))
        #expect(SimilarityPreset.allCases.map(\.threshold.value) == [0.96, 0.92, 0.85])
    }
}
