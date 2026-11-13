import CoreGraphics
import Foundation
import SwiftData
import Testing
@testable import QdrantPhotoSweep

#if targetEnvironment(simulator)
private let isPhysicalDevice = false
#else
private let isPhysicalDevice = true
#endif

@Suite(.serialized)
@MainActor
struct ScanLifecycleTests {
    private func makeStore() throws -> (ModelContainer, SwiftDataScanStore) {
        let schema = Schema([
            ScanSessionEntity.self, PhotoPointEntity.self, SimilarityEdgeEntity.self,
            DuplicateGroupEntity.self, GroupMemberEntity.self
        ])
        let container = try ModelContainer(
            for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return (container, SwiftDataScanStore(modelContainer: container))
    }

    private func pipeline(
        store: SwiftDataScanStore, vectors: RecordingVectors,
        photos: FixturePhotos = FixturePhotos()
    ) -> ScanPipeline {
        ScanPipeline(
            photoLibrary: photos, embeddingService: MockEmbeddingService(),
            vectorStore: vectors, scanStore: store, configureDimensions: { _ in }
        )
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(condition())
    }

    @Test(.enabled(if: isPhysicalDevice, "Vision feature prints need a physical device; simulators fail to create an espresso context"))
    func visionFeaturePrintRunsWithSelectedComputeDevices() async throws {
        let photos = FixturePhotos()
        let asset = try #require(try await photos.fetchAssets(
            in: DateRange(start: .distantPast, end: .now)
        ).first)
        let image = try await photos.loadThumbnail(for: asset, size: CGSize(width: 224, height: 224))
        let vector = try await VisionEmbeddingService().embed(image: image)
        #expect(!vector.isEmpty)
        let isFinite = vector.allSatisfy { $0.isFinite }
        #expect(isFinite)
    }

    @Test func coordinatorResumesTheSessionCreatedByItsPipeline() async throws {
        let (container, store) = try makeStore()
        let vectors = RecordingVectors()
        await vectors.failNextSearch()
        let deps = TestDependencies(vectorStore: vectors, photoLibrary: FixturePhotos(), scanStore: store)
        let coordinator = ContinuousScanCoordinator()
        coordinator.startPipeline(
            dateRange: DateRange(start: .distantPast, end: .now), resumeSessionId: nil, deps: deps
        )
        try await waitUntil {
            if case .failed = coordinator.phase { return true }
            return false
        }
        let interrupted = try #require(try await store.latestInterruptedSession())
        coordinator.resumeIfInterrupted()
        #expect(coordinator.phase == .failed(.vectorStore("Injected search failure")))
        coordinator.retryFailedScan()
        try await waitUntil {
            if case .completed = coordinator.phase { return true }
            return false
        }
        #expect(try await store.latestCompletedSession()?.id == interrupted.id)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<ScanSessionEntity>()) == 1)
    }

    @Test func embeddingFailureStopsImmediatelyAndPreservesTheError() async throws {
        let (_, store) = try makeStore()
        let embeddings = FailingEmbeddings()
        let pipeline = ScanPipeline(
            photoLibrary: FixturePhotos(count: 100), embeddingService: embeddings,
            vectorStore: RecordingVectors(), scanStore: store, configureDimensions: { _ in }
        )
        let outcome = await pipeline.run(
            dateRange: DateRange(start: .distantPast, end: .now), state: ScanState()
        )
        guard case .failed(let error) = outcome.status else {
            Issue.record("Expected an embedding failure")
            return
        }
        #expect(error == .embedding("Missing model weights"))
        #expect(await embeddings.calls == 1)
        #expect(try await store.latestCompletedSession() == nil)
    }

    @Test func failedSearchIsRetriedEvenAfterVectorUpsert() async throws {
        let (_, store) = try makeStore()
        let vectors = RecordingVectors()
        await vectors.failNextSearch()
        let pipeline = pipeline(store: store, vectors: vectors)
        let range = DateRange(start: .distantPast, end: .now)
        let first = await pipeline.run(dateRange: range, state: ScanState())
        #expect(!first.succeeded)
        let id = try #require(first.sessionId)
        let pointId = deterministicUUID(from: "fixture-photo")
        #expect(try await vectors.exists(id: pointId))
        #expect(try await !store.isDetectionComplete(vectorUUID: pointId, threshold: 0.92))
        #expect(try await store.latestInterruptedSession()?.id == id)

        let second = await pipeline.run(dateRange: range, state: ScanState(), resumeSessionId: id)
        #expect(second.succeeded)
        #expect(second.sessionId == id)
        #expect(await vectors.searchCount == 2)
        #expect(try await store.isDetectionComplete(vectorUUID: pointId, threshold: 0.92))
        #expect(try await store.latestCompletedSession()?.id == id)
    }

    @Test func cancellationInFinalBatchDoesNotMarkScanComplete() async throws {
        let (_, store) = try makeStore()
        let vectors = RecordingVectors()
        await vectors.cancelNextSearch()
        let pipeline = pipeline(store: store, vectors: vectors)
        let range = DateRange(start: .distantPast, end: .now)
        let worker = Task { await pipeline.run(dateRange: range, state: ScanState()) }
        let outcome = await worker.value
        #expect(!outcome.succeeded)
        #expect(try await store.latestCompletedSession() == nil)
        let pointId = deterministicUUID(from: "fixture-photo")
        #expect(try await !store.isDetectionComplete(vectorUUID: pointId, threshold: 0.92))
        let resumed = await pipeline.run(dateRange: range, state: ScanState(), resumeSessionId: outcome.sessionId)
        #expect(resumed.succeeded)
        #expect(await vectors.searchCount == 2)
    }

    @Test func detectionDoesNotRequireUICallbackAndUsesConfiguredThreshold() async throws {
        let (_, store) = try makeStore()
        let vectors = RecordingVectors()
        let pipeline = ScanPipeline(
            photoLibrary: FixturePhotos(), embeddingService: MockEmbeddingService(),
            vectorStore: vectors, scanStore: store,
            configureDimensions: { _ in }, similarityThreshold: 0.97
        )
        let result = await pipeline.run(
            dateRange: DateRange(start: .distantPast, end: .now), state: ScanState()
        )
        #expect(result.succeeded)
        #expect(await vectors.lastThreshold == 0.97)
        #expect(try await store.isDetectionComplete(
            vectorUUID: deterministicUUID(from: "fixture-photo"), threshold: 0.97
        ))
        #expect(try await !store.isDetectionComplete(
            vectorUUID: deterministicUUID(from: "fixture-photo"), threshold: 0.92
        ))
    }

    @Test func repeatedEdgesAreIdempotent() async throws {
        let (container, store) = try makeStore()
        let session = try await store.createSession(rangeStart: .distantPast, rangeEnd: .now, totalPhotos: 2)
        try await store.recordSimilarityEdge(source: "a", target: "b", score: 0.95, sessionId: session)
        try await store.recordSimilarityEdge(source: "b", target: "a", score: 0.96, sessionId: session)
        let edges = try ModelContext(container).fetch(FetchDescriptor<SimilarityEdgeEntity>())
        #expect(edges.count == 1)
        #expect(edges.first?.score == 0.96)
    }

    @Test func recoveryFindsScanningSessionsButNotUserCancelledSessions() async throws {
        let (_, store) = try makeStore()
        let stale = try await store.createSession(rangeStart: .distantPast, rangeEnd: .now, totalPhotos: 1)
        let cancelled = try await store.createSession(rangeStart: .distantPast, rangeEnd: .now, totalPhotos: 1)
        try await store.updateSessionStatus(cancelled, status: .cancelled, indexedPhotos: nil)
        try await store.interruptActiveSessions()
        #expect(try await store.latestInterruptedSession()?.id == stale)
    }

    @Test func incrementalRangeIncludesPhotosAfterPreviousRangeEnd() {
        let now = Date(timeIntervalSince1970: 1_000)
        let session = ScanSessionDTO(
            id: UUID(), rangeStart: .distantPast,
            rangeEnd: Date(timeIntervalSince1970: 100),
            scannedAt: Date(timeIntervalSince1970: 110),
            status: .completed, totalPhotos: 1, indexedPhotos: 1
        )
        let range = BackgroundScanService.incrementalRange(since: session, now: now)
        #expect(range?.start == session.scannedAt)
        #expect(range?.end == now)
    }

    @Test func foregroundWaitsForBackgroundCleanupAndBackgroundCannotOverlap() async {
        let controller = ScanExecutionController()
        let started = Signal()
        let cancelled = Signal()
        let releaseCleanup = Signal()
        var replacementStarted = false
        let background = Task {
            await controller.run(replacingCurrent: false) {
                started.open()
                do { try await Task.sleep(for: .seconds(60)) } catch {}
                cancelled.open()
                await releaseCleanup.wait()
                return ScanOutcome(sessionId: nil, status: .interrupted, groupsFound: 0)
            }
        }
        await started.wait()
        let rejected = await controller.run(replacingCurrent: false) {
            Issue.record("A second background scan must not start")
            return ScanOutcome(sessionId: nil, status: .completed, groupsFound: 0)
        }
        #expect(rejected == nil)
        let foreground = Task {
            await controller.run(replacingCurrent: true) {
                replacementStarted = true
                return ScanOutcome(sessionId: nil, status: .completed, groupsFound: 0)
            }
        }
        await cancelled.wait()
        #expect(!replacementStarted)
        releaseCleanup.open()
        #expect(await foreground.value?.succeeded == true)
        _ = await background.value
        #expect(replacementStarted)
        #expect(!controller.isRunning)
    }

    @Test func cancellationBeforePhotosContinuationInstallationResumesImmediately() async {
        let request = PhotoImageRequest()
        request.cancel()
        do {
            let _: CGImage = try await withCheckedThrowingContinuation { continuation in
                #expect(!request.install(continuation))
            }
            Issue.record("Cancelled request unexpectedly returned an image")
        } catch {
            #expect(error is CancellationError)
        }
    }

    @Test func photosCancellationCompletesContinuationOnlyOnce() async {
        let request = PhotoImageRequest()
        do {
            let _: CGImage = try await withCheckedThrowingContinuation { continuation in
                #expect(request.install(continuation))
                request.cancel()
                request.cancel()
                request.finish(.failure(AppError.photoLibrary("Late callback")))
            }
            Issue.record("Cancelled request unexpectedly returned an image")
        } catch {
            #expect(error is CancellationError)
        }
    }

    @Test func explicitCancelPersistsCancellationBeforeReplacementStarts() async throws {
        let (_, store) = try makeStore()
        let photos = FixturePhotos()
        let vectors = RecordingVectors()
        let deps = TestDependencies(
            vectorStore: vectors, photoLibrary: photos, scanStore: store
        )
        let coordinator = ContinuousScanCoordinator()
        await vectors.blockSearch()
        coordinator.startPipeline(
            dateRange: DateRange(start: .distantPast, end: .now), resumeSessionId: nil, deps: deps
        )
        await vectors.waitForSearch()
        await coordinator.cancel()
        #expect(coordinator.phase == .idle)
        #expect(try await store.latestInterruptedSession() == nil)
        #expect(!ScanExecutionController.shared.isRunning)
        coordinator.resumeIfInterrupted()
        #expect(coordinator.phase == .idle)
        await vectors.unblockSearch()
        coordinator.startPipeline(
            dateRange: DateRange(start: .distantPast, end: .now), resumeSessionId: nil, deps: deps
        )
        try await waitUntil {
            if case .completed = coordinator.phase { return true }
            return false
        }
        #expect(try await store.latestCompletedSession() != nil)
        #expect(try await store.latestInterruptedSession() == nil)
    }
}

@MainActor
private final class Signal {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        let pending = waiters
        waiters.removeAll()
        for waiter in pending { waiter.resume() }
    }
}

private final class FixturePhotos: PhotoLibraryProviding, @unchecked Sendable {
    let count: Int
    init(count: Int = 1) { self.count = count }
    func requestAuthorization() async throws(AppError) {}
    func fetchAssets(in dateRange: DateRange) async throws(AppError) -> [PhotoAsset] {
        (0..<count).map { index in
            let id = index == 0 ? "fixture-photo" : "fixture-photo-\(index)"
            return PhotoAsset(id: id, localIdentifier: id, creationDate: .now,
                              pixelWidth: 1, pixelHeight: 1, fileSize: nil)
        }
    }
    func countAssets(in dateRange: DateRange) async throws(AppError) -> Int { 1 }
    func loadThumbnail(for asset: PhotoAsset, size: CGSize) async throws(AppError) -> CGImage {
        guard let context = CGContext(
            data: nil, width: 224, height: 224, bitsPerComponent: 8, bytesPerRow: 224 * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let image = context.makeImage() else {
            throw .photoLibrary("Unable to create fixture")
        }
        return image
    }
    func loadFullImage(for asset: PhotoAsset) async throws(AppError) -> CGImage {
        try await loadThumbnail(for: asset, size: .zero)
    }
    func deleteAssets(_ identifiers: [String]) async throws(AppError) {}
}

private actor RecordingVectors: VectorStoring {
    private var ids: Set<String> = []
    private var shouldFail = false
    private var shouldCancel = false
    private var shouldBlock = false
    private var searchStarted = false
    private var searchWaiter: CheckedContinuation<Void, Never>?
    private(set) var searchCount = 0
    private(set) var lastThreshold: Float?

    func failNextSearch() { shouldFail = true }
    func cancelNextSearch() { shouldCancel = true }
    func blockSearch() { shouldBlock = true }
    func unblockSearch() { shouldBlock = false }
    func waitForSearch() async {
        if searchStarted { return }
        await withCheckedContinuation { searchWaiter = $0 }
    }

    func exists(id: String) async throws(AppError) -> Bool { ids.contains(id) }
    func upsert(points: [VectorPoint]) async throws(AppError) { ids.formUnion(points.map(\.id)) }
    func search(vector: [Float], limit: Int, threshold: Float) async throws(AppError) -> [ScoredResult] {
        searchCount += 1
        lastThreshold = threshold
        searchStarted = true
        searchWaiter?.resume()
        searchWaiter = nil
        if shouldFail {
            shouldFail = false
            throw .vectorStore("Injected search failure")
        }
        if shouldCancel {
            shouldCancel = false
            withUnsafeCurrentTask { $0?.cancel() }
        }
        if shouldBlock {
            do { try await Task.sleep(for: .seconds(60)) } catch {}
        }
        return []
    }
    func scroll(offset: String?, limit: Int) async throws(AppError) -> ScrollPage {
        ScrollPage(records: [], nextOffset: nil)
    }
    func delete(ids: [String]) async throws(AppError) { self.ids.subtract(ids) }
    func count() async throws(AppError) -> Int { ids.count }
    func close() async {}
}

private actor FailingEmbeddings: EmbeddingProviding {
    private(set) var calls = 0
    func embed(image: CGImage) async throws(AppError) -> [Float] {
        calls += 1
        throw .embedding("Missing model weights")
    }
}
