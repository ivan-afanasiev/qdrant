import CoreGraphics
import Foundation

public struct PhotoAsset: Identifiable, Hashable, Sendable {
    public let id: String
    public let localIdentifier: String
    public let creationDate: Date?
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let fileSize: Int64?
    /// Last content edit reported by Photos; drives re-vectorization of edited photos.
    public let modificationDate: Date?

    public var resolution: String {
        "\(pixelWidth) × \(pixelHeight)"
    }
    public init(
        id: String,
        localIdentifier: String,
        creationDate: Date?,
        pixelWidth: Int,
        pixelHeight: Int,
        fileSize: Int64?,
        modificationDate: Date? = nil
    ) {
        self.id = id
        self.localIdentifier = localIdentifier
        self.creationDate = creationDate
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.fileSize = fileSize
        self.modificationDate = modificationDate
    }

    /// Content revision used for vector reuse. Assets without a modification date
    /// share one revision, so they are vectorized once and reused afterwards.
    public var contentRevision: AssetContentRevision {
        guard let modificationDate else { return AssetContentRevision("unknown") }
        return AssetContentRevision(String(modificationDate.timeIntervalSince1970))
    }
}

/// How much of the library the app can see. Only `.full` lets a missing photo count as deleted.
public enum PhotoAccessScope: Equatable, Sendable {
    case full
    case limited
    case none
}

public protocol PhotoLibraryProviding: Sendable {
    func requestAuthorization() async throws(AdapterError)
    func accessScope() async -> PhotoAccessScope
    /// The accessible photos among `identifiers`; missing ones are absent from the result.
    func assets(withIdentifiers identifiers: [String]) async throws(AdapterError) -> [PhotoAsset]
    func fetchAssets(in dateRange: DateRange) async throws(AdapterError) -> [PhotoAsset]
    func countAssets(in dateRange: DateRange) async throws(AdapterError) -> Int
    func loadThumbnail(for asset: PhotoAsset, size: CGSize) async throws(AdapterError) -> CGImage
    func loadFullImage(for asset: PhotoAsset) async throws(AdapterError) -> CGImage
    func deleteAssets(_ identifiers: [String]) async throws(AdapterError)
}

public struct DateRange: Equatable, Sendable {
    public let start: Date
    public let end: Date

    public static var allTime: DateRange {
        DateRange(start: .distantPast, end: .now)
    }
    public init(start: Date, end: Date) {
        self.start = start
        self.end = end
    }
}
