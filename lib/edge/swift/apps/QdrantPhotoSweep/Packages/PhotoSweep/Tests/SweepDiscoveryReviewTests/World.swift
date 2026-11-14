import Foundation
import Testing
import SweepDomain
import SweepPersistence
import SweepTestSupport
import SweepUseCases

/// A photo with a controlled feature vector: 2-D unit vector at `degrees`.
/// Cosine similarity of two photos is cos(Δangle); at threshold 0.9 photos match within ~25°.
struct SeededPhoto {
    let id: String
    let day: Int?
    let degrees: Double
    var fileSize: Int64? = 1_000
}

let compatibility = EmbeddingCompatibility(model: "fake", modelRevision: 1, preprocessing: "thumbnail-224-fast", dimensions: 2)

/// A device with photos, committed vectors and an open review gate.
final class World {
    private static let root = FileManager.default.temporaryDirectory
        .appending(path: "PhotoSweepDiscoveryTests", directoryHint: .isDirectory)
    private static let removePreviousRuns: Void = {
        try? FileManager.default.removeItem(at: root)
    }()

    let storeURL: URL
    let library = FakePhotoLibrary()
    let vectorStores = FakeVectorStoreProvider()
    let ids = SequentialIDGenerator(startingAt: 10_000)
    private(set) var store: SwiftDataMetadataStore
    private var writes: UInt64 = 0

    init(
        _ photos: [SeededPhoto],
        threshold: Float = 0.9,
        scope: DateRange = DateRange(start: .distantPast, end: .distantFuture)
    ) async throws {
        Self.removePreviousRuns
        let directory = Self.root.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        storeURL = directory.appending(path: "metadata.store")
        store = SwiftDataMetadataStore(container: try MetadataStoreFactory.makeContainer(storeURL: storeURL), ids: ids)
        guard let threshold = SimilarityThreshold(threshold) else { throw WorldError.invalidThreshold }
        try await store.saveWorkflowState(WorkflowState(
            scope: scope,
            threshold: threshold,
            pause: .none,
            gate: InitialPassGate(state: .open(deferredCount: 0)),
            discoveryRevision: DiscoveryRevision(1),
            indexGeneration: IndexGeneration(1),
            indexCompatibility: compatibility
        ))
        try await add(photos)
    }

    enum WorldError: Error {
        case invalidThreshold
    }

    static func date(_ day: Int?) -> Date? {
        day.map { Date(timeIntervalSince1970: Double($0) * 86_400) }
    }

    /// Adds photos to the library and commits their vectors, as a finished vectorization would.
    func add(_ photos: [SeededPhoto]) async throws {
        let assets = photos.map {
            PhotoAsset(id: $0.id, localIdentifier: $0.id, creationDate: Self.date($0.day), pixelWidth: 10, pixelHeight: 10, fileSize: $0.fileSize)
        }
        await library.setAssets(await library.assets + assets)
        let records = try await store.register(assets.map {
            DiscoveredAsset(id: AssetID($0.localIdentifier), creationDate: $0.creationDate, contentRevision: $0.contentRevision)
        })
        let byID = Dictionary(uniqueKeysWithValues: photos.map { ($0.id, $0) })
        let items = records.compactMap { record -> VectorWriteItem? in
            guard let photo = byID[record.id.rawValue] else { return nil }
            let radians = photo.degrees * .pi / 180
            return VectorWriteItem(
                intent: VectorWriteIntent(assetID: record.id, pointID: record.pointID, contentRevision: record.contentRevision, compatibility: compatibility, generation: IndexGeneration(1)),
                vector: [Float(cos(radians)), Float(sin(radians))],
                payloadJson: VectorPayload(asset: record.id, creationDate: record.creationDate).json
            )
        }
        writes += 1
        try await VectorWriteTransaction(journal: store, vectorStore: try await vectors(), ids: SequentialIDGenerator(startingAt: 50_000 + writes * 1_000))
            .write(items, pass: nil)
    }

    func vectors() async throws -> FakeVectorStore {
        try await vectorStores.fakeStore(for: IndexGeneration(1), dimensions: 2)
    }

    /// Simulates a relaunch: a new store instance on the same file.
    func relaunch() throws {
        store = SwiftDataMetadataStore(container: try MetadataStoreFactory.makeContainer(storeURL: storeURL), ids: ids)
    }

    func discovery(capacity: Int = 3, pageSize: Int = 4) throws -> DiscoveryExecutor {
        guard let buffer = ReviewBufferPolicy(capacity: capacity) else { throw WorldError.invalidThreshold }
        return DiscoveryExecutor(
            dependencies: .init(vectorStores: vectorStores, assets: store, discovery: store, progress: store, review: store, workflow: store, ids: ids),
            configuration: DiscoveryConfiguration(buffer: buffer, pageSize: pageSize)
        )
    }

    var finisher: FinishConfirmedDeletion {
        FinishConfirmedDeletion(assets: store, vectorStores: vectorStores, workflow: store, deletion: store)
    }

    var loadNext: LoadNextReviewGroup {
        LoadNextReviewGroup(review: store, progress: store, workflow: store, journal: store)
    }

    func skip(refilling discovery: DiscoveryExecutor) -> SkipGroup {
        SkipGroup(review: store) { await discovery.requestRefill() }
    }

    func commit(refilling discovery: DiscoveryExecutor) -> CommitReviewDecision {
        CommitReviewDecision(review: store, journal: store, library: library, finisher: finisher) { await discovery.requestRefill() }
    }

    func recovery() -> RecoverPendingOperations {
        RecoverPendingOperations(
            journal: store,
            vectorWrites: store,
            vectorStore: FakeVectorStore(),
            reset: ResetLocalData(resetting: store, workflow: store, vectorStore: FakeVectorStore(), ids: ids),
            deletions: ReconcileDeletion(library: library, journal: store, finisher: finisher)
        )
    }

    /// Refills and waits for discovery to settle.
    func refill(_ discovery: DiscoveryExecutor) async {
        await discovery.requestRefill()
        await discovery.waitUntilIdle()
    }

    /// Current fresh groups as sets of photo names, in review order.
    func freshGroups(revision: Int = 1) async throws -> [Set<String>] {
        var result: [Set<String>] = []
        for id in try await store.reviewQueue(for: DiscoveryRevision(revision)).fresh {
            let group = try #require(try await store.group(id))
            result.append(Set(group.members.map(\.rawValue)))
        }
        return result
    }
}
