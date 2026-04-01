import CoreGraphics
import Foundation

struct PhotoAsset: Identifiable, Hashable, Sendable {
    let id: String
    let localIdentifier: String
    let creationDate: Date?
    let pixelWidth: Int
    let pixelHeight: Int
    let fileSize: Int64?

    var resolution: String {
        "\(pixelWidth) × \(pixelHeight)"
    }
}

protocol PhotoLibraryProviding: Sendable {
    func requestAuthorization() async throws(AppError)
    func fetchAssets(in dateRange: DateRange) async throws(AppError) -> [PhotoAsset]
    func countAssets(in dateRange: DateRange) async throws(AppError) -> Int
    func loadThumbnail(for asset: PhotoAsset, size: CGSize) async throws(AppError) -> CGImage
    func loadFullImage(for asset: PhotoAsset) async throws(AppError) -> CGImage
    func deleteAssets(_ identifiers: [String]) async throws(AppError)
}

struct DateRange: Equatable, Sendable {
    let start: Date
    let end: Date

    static var allTime: DateRange {
        DateRange(start: .distantPast, end: .now)
    }
}
