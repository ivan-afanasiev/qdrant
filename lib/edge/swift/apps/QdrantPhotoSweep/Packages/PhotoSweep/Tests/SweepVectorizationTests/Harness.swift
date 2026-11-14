import CoreGraphics
import Foundation
import Testing
import SweepDomain
import SweepPersistence
import SweepTestSupport
import SweepUseCases

func photo(_ id: String, day: Int = 1, modified: Double = 0) -> PhotoAsset {
    PhotoAsset(
        id: id, localIdentifier: id,
        creationDate: Date(timeIntervalSince1970: TimeInterval(day) * 86_400),
        pixelWidth: 4032, pixelHeight: 3024, fileSize: nil,
        modificationDate: Date(timeIntervalSince1970: modified)
    )
}

/// Embedder that suspends on a chosen call until its gate opens or the task is cancelled,
/// so tests can pause or interrupt a pass at an exact point without timing.
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

/// One simulated device: photo library, model, vector shards and a metadata store file
/// that survives "relaunches" (new executor and store instances on the same file).
final class Harness {
    private static let root = FileManager.default.temporaryDirectory
        .appending(path: "PhotoSweepVectorizationTests", directoryHint: .isDirectory)
    private static let removePreviousRuns: Void = {
        try? FileManager.default.removeItem(at: root)
    }()

    let storeURL: URL
    let library: FakePhotoLibrary
    let vectorStores = FakeVectorStoreProvider()
    let sleeper = RecordingSleeper()
    let ids = SequentialIDGenerator(startingAt: 1_000)

    init(photos: [PhotoAsset]) throws {
        Self.removePreviousRuns
        let directory = Self.root.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        storeURL = directory.appending(path: "metadata.store")
        library = FakePhotoLibrary(assets: photos)
    }

    func openStore() throws -> SwiftDataMetadataStore {
        SwiftDataMetadataStore(container: try MetadataStoreFactory.makeContainer(storeURL: storeURL), ids: ids)
    }

    /// A new executor over a freshly opened store, as after an app relaunch.
    func launch(
        embedder: some EmbeddingProviding & EmbeddingModelDescribing,
        configuration: VectorizationConfiguration = VectorizationConfiguration(batchSize: 2)
    ) throws -> (VectorizationExecutor, SwiftDataMetadataStore) {
        let store = try openStore()
        let executor = VectorizationExecutor(
            dependencies: .init(
                library: library, embedder: embedder, model: embedder, vectorStores: vectorStores,
                assets: store, passes: store, workflow: store, journal: store,
                ids: ids, sleeper: sleeper
            ),
            configuration: configuration
        )
        return (executor, store)
    }

    func vectors(generation: Int = 1, dimensions: Int = 3) async throws -> FakeVectorStore {
        try await vectorStores.fakeStore(for: IndexGeneration(generation), dimensions: dimensions)
    }

    /// Runs one trigger to completion of all resulting passes.
    @discardableResult
    func run(_ executor: VectorizationExecutor, _ trigger: VectorizationTrigger = .appActivation) async -> VectorizationTriggerOutcome {
        let outcome = await executor.handle(trigger)
        await executor.waitUntilIdle()
        return outcome
    }
}

/// Yields until `condition` holds; fails instead of hanging. No wall-clock sleeps.
func eventually(_ description: Comment, _ condition: () async throws -> Bool) async throws {
    for _ in 0..<20_000 {
        if try await condition() { return }
        await Task.yield()
    }
    Issue.record("Condition never became true: \(description)")
}
