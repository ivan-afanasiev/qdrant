import CoreGraphics
import SweepDomain

/// Image access for review screens, bound to `LoadReviewImage`. Cards show a thumbnail first,
/// then a high-quality image sized to the card; the full-screen preview loads the original.
public struct ReviewImages: Sendable {
    public var details: @Sendable ([AssetID]) async -> [AssetID: PhotoAsset]
    public var thumbnail: @Sendable (AssetID, _ pixels: Int) async -> CGImage?
    public var display: @Sendable (AssetID, _ maxPixels: Int) async -> CGImage?
    public var original: @Sendable (AssetID) async -> CGImage?

    public init(
        details: @escaping @Sendable ([AssetID]) async -> [AssetID: PhotoAsset],
        thumbnail: @escaping @Sendable (AssetID, _ pixels: Int) async -> CGImage?,
        display: @escaping @Sendable (AssetID, _ maxPixels: Int) async -> CGImage?,
        original: @escaping @Sendable (AssetID) async -> CGImage?
    ) {
        self.details = details
        self.thumbnail = thumbnail
        self.display = display
        self.original = original
    }
}
