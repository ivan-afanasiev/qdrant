import SafeDI
import SweepDomain

/// Inert integration probe. It never accesses the photo library or a production store.
@Instantiable(fulfillingAdditionalTypes: [BootstrapResource.self])
public actor BootstrapProbe: BootstrapResource, Instantiable {
    public init() {}
    public func prepare() async throws {}
}
