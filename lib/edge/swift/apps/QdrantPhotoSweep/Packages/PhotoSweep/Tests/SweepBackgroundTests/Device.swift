import CoreGraphics
import Foundation
import SweepDomain
import SweepPersistence
import SweepTestSupport
import SweepUseCases

/// Embedder that suspends on a chosen call until its gate opens or the task is cancelled.
actor GatedEmbedder: EmbeddingProviding, EmbeddingModelDescribing {
    let gate = AsyncGate()
    private let blockOnCall: Int
    private(set) var calls = 0

    init(blockOnCall: Int) {
        self.blockOnCall = blockOnCall
    }

    func embed(image: CGImage) async throws(AdapterError) -> [Float] {
        calls += 1
        if calls == blockOnCall {
            let gate = gate
            await withTaskCancellationHandler {
                await gate.wait()
            } onCancel: {
                Task { await gate.open() }
            }
        }
        return [1, 0, 0]
    }

    func modelDescriptor() async throws(AdapterError) -> EmbeddingModelDescriptor {
        EmbeddingModelDescriptor(model: "fake", revision: 1, dimensions: 3)
    }
}

/// A simulated iPhone: library, store file, both executors and the lifecycle coordinator.
/// All photos share one vector, so once vectorized they form a single review group.
final class Device: Sendable {
    private static let root = FileManager.default.temporaryDirectory
        .appending(path: "PhotoSweepBackgroundTests", directoryHint: .isDirectory)
    private static let removePreviousRuns: Void = {
        try? FileManager.default.removeItem(at: root)
    }()

    let library: FakePhotoLibrary
    let vectorStores = FakeVectorStoreProvider()
    let scheduler = FakeBackgroundScheduler()
    let notifier: FakeReviewNotifier
    let ids = SequentialIDGenerator(startingAt: 1_000)
    let store: SwiftDataMetadataStore
    let vectorization: VectorizationExecutor
    let discovery: DiscoveryExecutor
    let coordinator: AppLifecycleCoordinator

    init(
        photoCount: Int,
        embedder: some EmbeddingProviding & EmbeddingModelDescribing = FakeEmbeddingProvider(),
        notificationPermission: NotificationPermission = .authorized
    ) throws {
        Self.removePreviousRuns
        let directory = Self.root.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        library = FakePhotoLibrary(assets: (1...photoCount).map { index in
            PhotoAsset(
                id: "p\(index)", localIdentifier: "p\(index)",
                creationDate: Date(timeIntervalSince1970: Double(index) * 86_400),
                pixelWidth: 10, pixelHeight: 10, fileSize: nil,
                modificationDate: Date(timeIntervalSince1970: 0)
            )
        })
        notifier = FakeReviewNotifier(permission: notificationPermission)
        store = SwiftDataMetadataStore(
            container: try MetadataStoreFactory.makeContainer(storeURL: directory.appending(path: "metadata.store")),
            ids: ids
        )
        vectorization = VectorizationExecutor(
            dependencies: .init(
                library: library, embedder: embedder, model: embedder, vectorStores: vectorStores,
                assets: store, passes: store, workflow: store, journal: store,
                ids: ids, sleeper: RecordingSleeper()
            ),
            configuration: VectorizationConfiguration(batchSize: 2)
        )
        discovery = DiscoveryExecutor(
            dependencies: .init(vectorStores: vectorStores, assets: store, discovery: store, progress: store, review: store, workflow: store, ids: ids)
        )
        coordinator = AppLifecycleCoordinator(dependencies: .init(
            vectorization: vectorization, discovery: discovery, scheduler: scheduler, notifier: notifier, workflow: store
        ))
    }

    func vectorCount() async throws -> Int {
        try await vectorStores.fakeStore(for: IndexGeneration(1), dimensions: 3).count()
    }

    func groupCount() async throws -> Int {
        guard let revision = try await store.loadWorkflowState()?.discoveryRevision else { return 0 }
        return try await store.reviewQueue(for: revision).readyCount
    }

    /// Waits on discovery's own status stream until it has finished refilling.
    func discoverySettled() async {
        for await update in discovery.updates() {
            if update.status == .exhausted || update.status == .bufferReady { return }
        }
    }

    var pause: PauseState? {
        get async throws { try await store.loadWorkflowState()?.pause }
    }
}
