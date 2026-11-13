import Testing
import SweepComposition
import SweepDomain
import SweepUseCases

@MainActor
struct CompositionTests {
    @Test func generatedGraphSharesAppResourcesAndSeparatesFeatures() {
        let root = PhotoSweepComposition()
        let first = root.makeLibraryStore()
        let second = root.makeLibraryStore()
        #expect(first !== second)
        #expect(first.bootstrap.resource === root.resource)
        #expect(second.bootstrap.resource === root.resource)
        #expect(root.foregroundEntry.resource === root.backgroundEntry.resource)
    }

    @Test func bootstrapIsExplicitAndRetryRetainsResource() async throws {
        let resource = RetryResource()
        let bootstrap = BootstrapApplication(resource: resource)
        #expect(await resource.attempts == 0)
        await #expect(throws: RetryResource.Failure.self) {
            try await bootstrap.execute()
        }
        try await bootstrap.execute()
        #expect(await resource.attempts == 2)
        #expect(bootstrap.resource === resource)
    }

    @Test func independentGraphsDoNotShareResources() {
        #expect(PhotoSweepComposition().resource !== PhotoSweepComposition().resource)
    }
}

private actor RetryResource: BootstrapResource {
    enum Failure: Error { case firstAttempt }
    private(set) var attempts = 0

    func prepare() async throws {
        attempts += 1
        if attempts == 1 { throw Failure.firstAttempt }
    }
}
