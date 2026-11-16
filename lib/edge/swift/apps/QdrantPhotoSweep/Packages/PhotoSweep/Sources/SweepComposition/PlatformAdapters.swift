import Foundation
import SafeDI
import SweepDomain
import SweepPersistence
import SweepQdrant

/// Every platform adapter the app uses, as contracts. One instance per app.
public struct PlatformServices: Sendable {
    public let location: LocalDataLocation
    public let library: any PhotoLibraryProviding
    public let libraryChanges: any PhotoLibraryChangeObserving
    public let embedder: any EmbeddingProviding & EmbeddingModelDescribing
    public let vectorStores: any VectorStoreProviding
    public let scheduler: any BackgroundExecutionScheduling
    public let notifier: any ReviewReadyNotifying

    public init(
        location: LocalDataLocation,
        library: any PhotoLibraryProviding,
        libraryChanges: any PhotoLibraryChangeObserving,
        embedder: any EmbeddingProviding & EmbeddingModelDescribing,
        vectorStores: any VectorStoreProviding,
        scheduler: any BackgroundExecutionScheduling,
        notifier: any ReviewReadyNotifying
    ) {
        self.location = location
        self.library = library
        self.libraryChanges = libraryChanges
        self.embedder = embedder
        self.vectorStores = vectorStores
        self.scheduler = scheduler
        self.notifier = notifier
    }
}

/// App-scoped holder of the platform adapters. Construction opens nothing: the metadata
/// store and vector shards are opened later by `RewriteBootstrap`.
@Instantiable
public final class PlatformAdapters: Instantiable, Sendable {
    public let services: PlatformServices

    /// Live adapters for the current platform.
    public init() {
        services = Self.liveServices()
    }

    /// Explicit adapters, for tests and previews.
    public init(services: PlatformServices) {
        self.services = services
    }

    static func liveServices() -> PlatformServices {
        let location = LocalDataLocation(applicationSupport: URL.applicationSupportDirectory)
        return PlatformServices(
            location: location,
            library: LivePlatform.library(),
            libraryChanges: LivePlatform.libraryChanges(),
            embedder: LivePlatform.embedder(),
            vectorStores: QdrantStoreProvider(root: location.vectorIndexDirectory),
            scheduler: LivePlatform.scheduler(),
            notifier: LivePlatform.notifier()
        )
    }
}
