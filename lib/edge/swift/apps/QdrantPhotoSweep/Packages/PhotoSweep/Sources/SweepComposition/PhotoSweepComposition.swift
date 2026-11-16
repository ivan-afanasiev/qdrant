import SafeDI
import SweepDomain

/// The app's single composition root. The host creates it once, outside SwiftUI body
/// reconstruction; foreground UI and background launches share it.
@MainActor
@Instantiable(isRoot: true)
public final class PhotoSweepComposition: Instantiable {
    @Instantiated public let adapters: PlatformAdapters
    @Instantiated public let bootstrap: RewriteBootstrap

    public init(adapters: PlatformAdapters, bootstrap: RewriteBootstrap) {
        self.adapters = adapters
        self.bootstrap = bootstrap
    }
}
