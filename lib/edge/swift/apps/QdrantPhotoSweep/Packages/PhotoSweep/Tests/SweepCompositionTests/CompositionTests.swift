import Foundation
import Testing
import SweepComposition
import SweepDomain
import SweepPersistence
import SweepTestSupport
import SweepUseCases

/// Fake platform rooted in a fresh temporary "Application Support" directory.
private struct FakePlatform {
    private static let root = FileManager.default.temporaryDirectory
        .appending(path: "PhotoSweepCompositionTests", directoryHint: .isDirectory)
    private static let removePreviousRuns: Void = {
        try? FileManager.default.removeItem(at: root)
    }()

    let support: URL
    let library = FakePhotoLibrary()
    let changes = FakePhotoLibraryChanges()
    let scheduler = FakeBackgroundScheduler()
    let vectorStores = FakeVectorStoreProvider()

    init() {
        Self.removePreviousRuns
        support = Self.root.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    }

    var location: LocalDataLocation { LocalDataLocation(applicationSupport: support) }

    var adapters: PlatformAdapters {
        PlatformAdapters(services: PlatformServices(
            location: location, library: library, libraryChanges: changes,
            embedder: FakeEmbeddingProvider(), vectorStores: vectorStores,
            scheduler: scheduler, notifier: FakeReviewNotifier()
        ))
    }
}

@MainActor
struct CompositionGraphTests {
    @Test func independentGraphsDoNotShareAppScopedInstances() {
        let first = PhotoSweepComposition()
        let second = PhotoSweepComposition()
        #expect(first.adapters !== second.adapters)
        #expect(first.bootstrap !== second.bootstrap)
    }

    @Test func constructionOpensNothing() async {
        let platform = FakePlatform()
        let bootstrap = RewriteBootstrap(adapters: platform.adapters)
        #expect(await bootstrap.current == nil)
        #expect(!FileManager.default.fileExists(atPath: platform.location.root.path))
    }
}

struct BootstrapTests {
    @Test func concurrentStartsShareOneAttemptAndRuntime() async throws {
        let platform = FakePlatform()
        let bootstrap = RewriteBootstrap(adapters: platform.adapters, ids: SequentialIDGenerator())
        async let first = bootstrap.start()
        async let second = bootstrap.start()
        let (a, b) = try await (first, second)
        #expect(a.store === b.store)
        #expect(a.vectorization === b.vectorization)
        #expect(await bootstrap.attemptCount == 1)
        #expect(try await bootstrap.start().lifecycle === a.lifecycle)
    }

    @Test func failedBootstrapCanBeRetriedWithoutSecondRuntime() async throws {
        let platform = FakePlatform()
        // A regular file where the namespace directory must go makes opening fail.
        try FileManager.default.createDirectory(at: platform.support.appending(path: "PhotoSweep"), withIntermediateDirectories: true)
        try Data().write(to: platform.location.root)
        let bootstrap = RewriteBootstrap(adapters: platform.adapters, ids: SequentialIDGenerator())

        await #expect(throws: BootstrapError.self) {
            _ = try await bootstrap.start()
        }
        #expect(await bootstrap.current == nil)

        try FileManager.default.removeItem(at: platform.location.root)
        let runtime = try await bootstrap.start()
        #expect(await bootstrap.attemptCount == 2)
        #expect(try await bootstrap.start().store === runtime.store)
    }

    @Test func interruptedWorkIsRecoveredAtLaunch() async throws {
        let platform = FakePlatform()
        try platform.location.prepare()
        let previous = SwiftDataMetadataStore(container: try MetadataStoreFactory.makeContainer(storeURL: platform.location.metadataStoreURL))
        let records = try await previous.register([DiscoveredAsset(id: AssetID("a"), creationDate: .now, contentRevision: AssetContentRevision("r"))])
        try await previous.beginVectorWrite(OperationID(UUID()), intents: [VectorWriteIntent(
            assetID: records[0].id, pointID: records[0].pointID, contentRevision: records[0].contentRevision,
            compatibility: EmbeddingCompatibility(model: "fake", modelRevision: 1, preprocessing: "p", dimensions: 3),
            generation: IndexGeneration(1)
        )])

        let runtime = try await RewriteBootstrap(adapters: platform.adapters, ids: SequentialIDGenerator()).start()
        #expect(try await runtime.store.openJournalEntries().isEmpty)
        #expect(try await runtime.store.assets([AssetID("a")])[AssetID("a")]?.state == .pending)
    }

    @Test func backgroundWindowBeforeAnyUIBootstrapsAndFinishesOnce() async throws {
        let platform = FakePlatform()
        let bootstrap = RewriteBootstrap(adapters: platform.adapters, ids: SequentialIDGenerator())
        let window = FakeExecutionWindow(kind: .scheduled)
        await bootstrap.deliver(window)
        #expect(window.finishCalls.count == 1)
        #expect(await bootstrap.current != nil)
    }

    @Test func libraryIsObservedOnlyAfterAccessIsGranted() async throws {
        let denied = FakePlatform()
        await denied.library.setAccessScope(.none)
        _ = try await RewriteBootstrap(adapters: denied.adapters, ids: SequentialIDGenerator()).start()
        #expect(denied.changes.observerCount == 0)

        let granted = FakePlatform()
        let runtime = try await RewriteBootstrap(adapters: granted.adapters, ids: SequentialIDGenerator()).start()
        #expect(granted.changes.observerCount == 1)
        await runtime.vectorization.stopObservingLibraryChanges()
    }
}
