import Foundation
import SweepDomain
import SweepPersistence
import SweepUseCases

/// Everything that exists only after local data is opened: the metadata store, the single
/// vectorization executor, the discovery executor and the lifecycle coordinator. Built once
/// by `RewriteBootstrap` and shared by foreground and background entry points.
public struct AppRuntime: Sendable {
    public let services: PlatformServices
    public let store: SwiftDataMetadataStore
    public let vectorization: VectorizationExecutor
    public let discovery: DiscoveryExecutor
    public let lifecycle: AppLifecycleCoordinator
    public let ids: any IDGenerating

    init(services: PlatformServices, store: SwiftDataMetadataStore, ids: any IDGenerating) {
        self.services = services
        self.store = store
        self.ids = ids
        vectorization = VectorizationExecutor(dependencies: .init(
            library: services.library, embedder: services.embedder, model: services.embedder,
            vectorStores: services.vectorStores, assets: store, passes: store, workflow: store,
            journal: store, ids: ids, sleeper: TaskSleeper()
        ))
        discovery = DiscoveryExecutor(dependencies: .init(
            vectorStores: services.vectorStores, assets: store, discovery: store,
            progress: store, review: store, workflow: store, ids: ids
        ))
        lifecycle = AppLifecycleCoordinator(dependencies: .init(
            vectorization: vectorization, discovery: discovery, scheduler: services.scheduler,
            notifier: services.notifier, workflow: store
        ))
    }

    /// Starts automatic vectorization on library changes once access exists, so that
    /// registering the Photos observer never happens before the person grants access.
    public func observeLibraryChangesIfAuthorized() async {
        guard await services.library.accessScope() != .none else { return }
        await vectorization.startObservingLibraryChanges(services.libraryChanges)
    }
}

/// Vector store used during recovery before any vector was ever written; nothing to roll back.
struct EmptyVectorStore: VectorStoring {
    func exists(id: String) async throws(AdapterError) -> Bool { false }
    func upsert(points: [VectorPoint]) async throws(AdapterError) {}
    func search(vector: [Float], limit: Int, threshold: Float) async throws(AdapterError) -> [ScoredResult] { [] }
    func searchPage(vector: [Float], threshold: Float, filter: VectorSearchFilter?, offset: Int, limit: Int) async throws(AdapterError) -> [ScoredResult] { [] }
    func vector(id: String) async throws(AdapterError) -> [Float]? { nil }
    func scroll(offset: String?, limit: Int) async throws(AdapterError) -> ScrollPage { ScrollPage(records: [], nextOffset: nil) }
    func delete(ids: [String]) async throws(AdapterError) {}
    func count() async throws(AdapterError) -> Int { 0 }
    func close() async {}
}
