import CoreGraphics
import Foundation

public struct PhotoAsset: Identifiable, Hashable, Sendable {
    public let id: String
    public let localIdentifier: String
    public let creationDate: Date?
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let fileSize: Int64?

    public var resolution: String {
        "\(pixelWidth) × \(pixelHeight)"
    }
    public init(id: String, localIdentifier: String, creationDate: Date?, pixelWidth: Int, pixelHeight: Int, fileSize: Int64?) {
        self.id = id
        self.localIdentifier = localIdentifier
        self.creationDate = creationDate
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.fileSize = fileSize
    }
}

public protocol PhotoLibraryProviding: Sendable {
    func requestAuthorization() async throws(AdapterError)
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
