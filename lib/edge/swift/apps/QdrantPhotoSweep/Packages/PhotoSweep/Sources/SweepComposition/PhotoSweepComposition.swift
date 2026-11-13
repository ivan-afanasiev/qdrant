import SafeDI
import SweepDomain
import SweepSystem
import SweepUseCases
import SweepLibraryFeature

@MainActor
@Instantiable(isRoot: true)
public final class PhotoSweepComposition: Instantiable {
    @Instantiated public let resource: any BootstrapResource
    @Instantiated public let bootstrap: BootstrapApplication
    @Instantiated private let libraryStore: Instantiator<LibraryStore>

    public init(resource: any BootstrapResource, bootstrap: BootstrapApplication,
                libraryStore: Instantiator<LibraryStore>) {
        self.resource = resource
        self.bootstrap = bootstrap
        self.libraryStore = libraryStore
    }

    public func makeLibraryStore() -> LibraryStore {
        libraryStore.instantiate()
    }

    public var foregroundEntry: BootstrapApplication { bootstrap }
    public var backgroundEntry: BootstrapApplication { bootstrap }
}
