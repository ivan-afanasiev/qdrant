import SafeDI
import SweepDomain

@Instantiable
public struct BootstrapApplication: Instantiable, Sendable {
    @Received public let resource: any BootstrapResource

    public init(resource: any BootstrapResource) {
        self.resource = resource
    }

    public func execute() async throws {
        try await resource.prepare()
    }
}
