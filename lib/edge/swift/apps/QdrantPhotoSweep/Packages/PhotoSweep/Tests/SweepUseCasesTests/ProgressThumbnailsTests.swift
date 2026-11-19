import CoreGraphics
import Foundation
import Testing
import SweepDomain
import SweepTestSupport
import SweepUseCases

private actor ProgressPasses: VectorizationPassRepository {
    var pass: VectorizationPass?
    init(_ pass: VectorizationPass?) { self.pass = pass }
    func activePass() -> VectorizationPass? { pass }
    func beginPass(_ pass: VectorizationPass) { self.pass = pass }
    func recordDeferred(_ deferrals: [AssetID: DeferralReason], pass: VectorizationPassID) { }
    func finishPass(_ id: VectorizationPassID) { pass = nil }
}

@Suite struct ProgressThumbnailsTests {
    @Test func sampleIsBoundedAndLoadsOnlyThumbnails() async {
        let assets = (0..<20).map { index in
            PhotoAsset(id: "\(index)", localIdentifier: "\(index)", creationDate: nil,
                       pixelWidth: 100, pixelHeight: 100, fileSize: nil)
        }
        let library = FakePhotoLibrary(assets: assets)
        let pass = VectorizationPass(id: VectorizationPassID(UUID()), kind: .initial,
                                    scope: .allTime, workSet: assets.map { AssetID($0.id) })
        let loader = LoadProgressThumbnails(passes: ProgressPasses(pass), library: library)
        let images = await loader.execute()
        #expect(images.count == 8)
        let requests = await library.imageRequests
        #expect(requests.count == 8)
        for request in requests {
            guard case .thumbnail(_, let size) = request else {
                Issue.record("Progress must load thumbnails only")
                continue
            }
            #expect(size == CGSize(width: 160, height: 160))
        }
        #expect(await library.fetchCount == 0)
    }

    @Test func absentPassDoesNotLoadPhotos() async {
        let library = FakePhotoLibrary()
        let images = await LoadProgressThumbnails(passes: ProgressPasses(nil), library: library).execute()
        #expect(images.isEmpty)
        #expect(await library.imageRequests.isEmpty)
    }

    @Test func inaccessiblePhotosAreOmitted() async {
        let pass = VectorizationPass(id: VectorizationPassID(UUID()), kind: .initial,
                                    scope: .allTime, workSet: [AssetID("missing")])
        let library = FakePhotoLibrary()
        let images = await LoadProgressThumbnails(passes: ProgressPasses(pass), library: library).execute()
        #expect(images.isEmpty)
        #expect(await library.deletedIdentifiers.isEmpty)
    }
}
