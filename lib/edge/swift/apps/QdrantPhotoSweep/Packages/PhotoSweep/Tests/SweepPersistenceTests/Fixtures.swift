import Foundation
import SweepDomain
import SweepPersistence
import SweepTestSupport
import SweepUseCases

/// A store file in its own temporary directory. Reopening creates a new container on the
/// same file, which is how tests simulate an app crash and relaunch.
///
/// Directories are not deleted in `deinit`: Swift may release this object right after its
/// last use while stores opened from it are still running. Leftovers from earlier runs are
/// removed once per test process instead.
final class TemporaryStore {
    private static let root = FileManager.default.temporaryDirectory
        .appending(path: "PhotoSweepPersistenceTests", directoryHint: .isDirectory)
    private static let removePreviousRuns: Void = {
        try? FileManager.default.removeItem(at: root)
    }()

    let directory: URL

    init() throws {
        Self.removePreviousRuns
        directory = Self.root.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    var url: URL { directory.appending(path: "metadata.store") }

    func open(ids: any IDGenerating = SequentialIDGenerator()) throws -> SwiftDataMetadataStore {
        SwiftDataMetadataStore(container: try MetadataStoreFactory.makeContainer(storeURL: url), ids: ids)
    }
}

let compatibility = EmbeddingCompatibility(model: "featurePrint", modelRevision: 2, preprocessing: "thumb-224", dimensions: 3)
let generation = IndexGeneration(1)
let scope = DateRange(start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 86_400 * 365))

func discovered(_ name: String, revision: String = "r1") -> DiscoveredAsset {
    DiscoveredAsset(id: AssetID(name), creationDate: Date(timeIntervalSince1970: 86_400), contentRevision: AssetContentRevision(revision))
}

func operation(_ value: UInt64) -> OperationID {
    OperationID(SequentialIDGenerator.uuid(value))
}

func groupID(_ value: UInt64) -> GroupID {
    GroupID(SequentialIDGenerator.uuid(value))
}

func passID(_ value: UInt64) -> VectorizationPassID {
    VectorizationPassID(SequentialIDGenerator.uuid(value))
}

func threshold(_ value: Float) throws -> SimilarityThreshold {
    guard let threshold = SimilarityThreshold(value) else { throw FixtureError.invalidThreshold }
    return threshold
}

enum FixtureError: Error {
    case invalidThreshold
}

func intent(for record: AssetRecord) -> VectorWriteIntent {
    VectorWriteIntent(
        assetID: record.id,
        pointID: record.pointID,
        contentRevision: record.contentRevision,
        compatibility: compatibility,
        generation: generation
    )
}

func items(for records: [AssetRecord]) -> [VectorWriteItem] {
    records.map { VectorWriteItem(intent: intent(for: $0), vector: [1, 0, 0], payloadJson: "{\"asset\":\"\($0.id)\"}") }
}

func snapshot(_ id: UInt64, revision: Int = 1, discovery: Int = 1, members: [String]) -> ReviewGroupSnapshot {
    ReviewGroupSnapshot(
        id: groupID(id),
        revision: MembershipRevision(revision),
        discoveryRevision: DiscoveryRevision(discovery),
        members: members.map(AssetID.init)
    )
}

func workflow(revision: Int = 1, generation: Int = 1, paused: Bool = false) throws -> WorkflowState {
    WorkflowState(
        scope: scope,
        threshold: try threshold(0.9),
        pause: PauseState(isPausedByUser: paused),
        gate: InitialPassGate(state: .open(deferredCount: 2)),
        discoveryRevision: DiscoveryRevision(revision),
        indexGeneration: IndexGeneration(generation)
    )
}

/// Builds the recovery use case over one store and vector store.
func recovery(store: SwiftDataMetadataStore, vectors: FakeVectorStore) -> RecoverPendingOperations {
    RecoverPendingOperations(
        journal: store,
        vectorWrites: store,
        vectorStore: vectors,
        reset: ResetLocalData(resetting: store, workflow: store, vectorStore: vectors, ids: SequentialIDGenerator(startingAt: 9_000))
    )
}
