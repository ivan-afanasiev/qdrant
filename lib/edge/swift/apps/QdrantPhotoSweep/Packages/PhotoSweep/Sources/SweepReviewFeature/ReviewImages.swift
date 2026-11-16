import CoreGraphics
import SweepDomain

/// Image access for review screens, bound to `LoadReviewImage`. Cards use thumbnails;
/// only the explicit preview loads full resolution.
public struct ReviewImages: Sendable {
    public var details: @Sendable ([AssetID]) async -> [AssetID: PhotoAsset]
    public var thumbnail: @Sendable (AssetID, _ pixels: Int) async -> CGImage?
    public var preview: @Sendable (AssetID) async -> CGImage?

    public init(
        details: @escaping @Sendable ([AssetID]) async -> [AssetID: PhotoAsset],
        thumbnail: @escaping @Sendable (AssetID, _ pixels: Int) async -> CGImage?,
        preview: @escaping @Sendable (AssetID) async -> CGImage?
    ) {
        self.details = details
        self.thumbnail = thumbnail
        self.preview = preview
    }
}
