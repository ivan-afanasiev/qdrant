import SafeDI
import SweepUseCases

/// Minimal feature boundary for the DI milestone; review state lands in step 4.
@MainActor
@Instantiable
public final class LibraryStore: Instantiable {
    @Received public let bootstrap: BootstrapApplication

    public init(bootstrap: BootstrapApplication) {
        self.bootstrap = bootstrap
    }
}
