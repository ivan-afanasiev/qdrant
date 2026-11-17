import CoreGraphics
import SweepDomain

/// Image access for review screens, bound to `LoadReviewImage`. Cards show a thumbnail first
/// and then the original; the full-screen preview loads the original directly.
public struct ReviewImages: Sendable {
    public var details: @Sendable ([AssetID]) async -> [AssetID: PhotoAsset]
    public var thumbnail: @Sendable (AssetID, _ pixels: Int) async -> CGImage?
    public var original: @Sendable (AssetID) async -> CGImage?

    public init(
        details: @escaping @Sendable ([AssetID]) async -> [AssetID: PhotoAsset],
        thumbnail: @escaping @Sendable (AssetID, _ pixels: Int) async -> CGImage?,
        original: @escaping @Sendable (AssetID) async -> CGImage?
    ) {
        self.details = details
        self.thumbnail = thumbnail
        self.original = original
    }
}
