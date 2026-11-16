import Foundation
import SafeDI
import SweepDomain
import SweepPersistence
import SweepUseCases

public enum BootstrapError: Error, Equatable, Sendable {
    case localData(PersistenceError)
    case recovery(LocalDataError)
    case vectorStore(AdapterError)
}

/// BootstrapApplication: opens local data, recovers interrupted operations and assembles the
/// app runtime exactly once. Concurrent callers share one attempt; a failed attempt can be
/// retried. Background launches use the same instance, so there is never a second graph or
/// a second shard owner.
@Instantiable
public actor RewriteBootstrap: Instantiable {
    @Received private let adapters: PlatformAdapters
    private let ids: any IDGenerating
    private var runtime: AppRuntime?
    private var attempt: Task<AppRuntime, any Error>?
    public private(set) var attemptCount = 0

    public init(adapters: PlatformAdapters) {
        self.adapters = adapters
        self.ids = SystemIDGenerator()
    }

    /// Explicit identifiers for tests.
    public init(adapters: PlatformAdapters, ids: any IDGenerating) {
        self.adapters = adapters
        self.ids = ids
    }

    public var current: AppRuntime? { runtime }

    public func start() async throws(BootstrapError) -> AppRuntime {
        if let runtime { return runtime }
        let task: Task<AppRuntime, any Error>
        if let attempt {
            task = attempt
        } else {
            attemptCount += 1
            let services = adapters.services
            let ids = ids
            task = Task { try await Self.open(services: services, ids: ids) }
            attempt = task
        }
        do {
            let opened = try await task.value
            runtime = opened
            attempt = nil
            return opened
        } catch let error as BootstrapError {
            attempt = nil
            throw error
        } catch {
            attempt = nil
            throw .localData(.storeUnavailable(String(describing: error)))
        }
    }

    /// Entry point for system background windows, which may arrive before any UI exists.
    public func deliver(_ window: any ExecutionWindow) async {
        do {
            let runtime = try await start()
            await runtime.lifecycle.run(window)
        } catch {
            window.finish(success: false)
        }
    }

    private static func open(services: PlatformServices, ids: any IDGenerating) async throws(BootstrapError) -> AppRuntime {
        let store: SwiftDataMetadataStore
        do {
            try services.location.prepare()
            store = SwiftDataMetadataStore(
                container: try MetadataStoreFactory.makeContainer(storeURL: services.location.metadataStoreURL),
                ids: ids
            )
        } catch {
            throw .localData(error)
        }
        try await recover(store: store, services: services, ids: ids)
        let runtime = AppRuntime(services: services, store: store, ids: ids)
        await runtime.observeLibraryChangesIfAuthorized()
        return runtime
    }

    /// RecoverPendingOperations before any new work: finish resets, roll back half-written
    /// vectors and reconcile deletions.
    private static func recover(store: SwiftDataMetadataStore, services: PlatformServices, ids: any IDGenerating) async throws(BootstrapError) {
        let vectorStore: any VectorStoring
        do {
            let state = try await store.loadWorkflowState()
            if let state, let compatibility = state.indexCompatibility {
                vectorStore = try await services.vectorStores.store(for: state.indexGeneration, dimensions: compatibility.dimensions)
            } else {
                vectorStore = EmptyVectorStore()
            }
        } catch let error as AdapterError {
            throw .vectorStore(error)
        } catch let error as PersistenceError {
            throw .localData(error)
        } catch {
            throw .localData(.storeUnavailable(String(describing: error)))
        }
        let finisher = FinishConfirmedDeletion(assets: store, vectorStores: services.vectorStores, workflow: store, deletion: store)
        do {
            _ = try await RecoverPendingOperations(
                journal: store,
                vectorWrites: store,
                vectorStore: vectorStore,
                reset: ResetLocalData(resetting: store, workflow: store, vectorStore: vectorStore, ids: ids),
                deletions: ReconcileDeletion(library: services.library, journal: store, finisher: finisher)
            ).execute()
        } catch {
            throw .recovery(error)
        }
    }
}
