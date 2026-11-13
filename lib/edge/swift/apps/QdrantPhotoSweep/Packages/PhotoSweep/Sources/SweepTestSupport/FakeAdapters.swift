import CoreGraphics
import Foundation
import SweepDomain

/// In-memory photo library that records every image request, so tests can prove
/// thumbnails are used for processing and full resolution only for preview.
public actor FakePhotoLibrary: PhotoLibraryProviding {
    public enum ImageRequest: Equatable, Sendable {
        case thumbnail(assetID: String, size: CGSize)
        case fullResolution(assetID: String)
    }

    public var assets: [PhotoAsset]
    public var authorizationError: AdapterError?
    /// Asset IDs whose image loads fail.
    public var unavailableAssetIDs: Set<String> = []
    public var deletionError: AdapterError?
    public private(set) var imageRequests: [ImageRequest] = []
    public private(set) var deletedIdentifiers: [[String]] = []

    public init(assets: [PhotoAsset] = []) {
        self.assets = assets
    }

    public func setUnavailable(_ ids: Set<String>) {
        unavailableAssetIDs = ids
    }

    public func setDeletionError(_ error: AdapterError?) {
        deletionError = error
    }

    public func setAuthorizationError(_ error: AdapterError?) {
        authorizationError = error
    }

    public func requestAuthorization() async throws(AdapterError) {
        if let authorizationError { throw authorizationError }
    }

    public func fetchAssets(in dateRange: DateRange) async throws(AdapterError) -> [PhotoAsset] {
        if let authorizationError { throw authorizationError }
        return assets.filter { dateRange.contains($0.creationDate) }
    }

    public func countAssets(in dateRange: DateRange) async throws(AdapterError) -> Int {
        try await fetchAssets(in: dateRange).count
    }

    public func loadThumbnail(for asset: PhotoAsset, size: CGSize) async throws(AdapterError) -> CGImage {
        imageRequests.append(.thumbnail(assetID: asset.id, size: size))
        return try image(for: asset)
    }

    public func loadFullImage(for asset: PhotoAsset) async throws(AdapterError) -> CGImage {
        imageRequests.append(.fullResolution(assetID: asset.id))
        return try image(for: asset)
    }

    public func deleteAssets(_ identifiers: [String]) async throws(AdapterError) {
        if let deletionError { throw deletionError }
        deletedIdentifiers.append(identifiers)
        let deleted = Set(identifiers)
        assets.removeAll { deleted.contains($0.localIdentifier) }
    }

    public var fullResolutionRequestCount: Int {
        imageRequests.filter {
            if case .fullResolution = $0 { return true }
            return false
        }.count
    }

    private func image(for asset: PhotoAsset) throws(AdapterError) -> CGImage {
        guard !unavailableAssetIDs.contains(asset.id) else {
            throw .photoLibrary("Asset \(asset.id) is unavailable")
        }
        guard let image = FakeImages.onePixel() else {
            throw .photoLibrary("Could not create a test image")
        }
        return image
    }
}

/// In-memory vector store with cosine search and failure injection.
public actor FakeVectorStore: VectorStoring {
    public private(set) var points: [String: VectorPoint] = [:]
    public private(set) var isClosed = false
    /// Thrown by the next operations until cleared.
    public var failure: AdapterError?

    public init() {}

    public func setFailure(_ failure: AdapterError?) {
        self.failure = failure
    }

    public func exists(id: String) async throws(AdapterError) -> Bool {
        try check()
        return points[id] != nil
    }

    public func upsert(points newPoints: [VectorPoint]) async throws(AdapterError) {
        try check()
        for point in newPoints {
            points[point.id] = point
        }
    }

    public func search(vector: [Float], limit: Int, threshold: Float) async throws(AdapterError) -> [ScoredResult] {
        try check()
        return points.values
            .map { ScoredResult(id: $0.id, score: Self.cosine(vector, $0.vector), payloadJson: $0.payloadJson, vectorJson: nil) }
            .filter { $0.score >= threshold }
            .sorted { $0.score == $1.score ? $0.id < $1.id : $0.score > $1.score }
            .prefix(limit)
            .map { $0 }
    }

    public func scroll(offset: String?, limit: Int) async throws(AdapterError) -> ScrollPage {
        try check()
        let ids = points.keys.sorted().filter { offset == nil || $0 >= (offset ?? "") }
        let page = ids.prefix(limit)
        let records = page.map { VectorRecord(id: $0, payloadJson: points[$0]?.payloadJson, vectorJson: nil) }
        let nextOffset = ids.count > limit ? ids[limit] : nil
        return ScrollPage(records: records, nextOffset: nextOffset)
    }

    public func delete(ids: [String]) async throws(AdapterError) {
        try check()
        for id in ids {
            points[id] = nil
        }
    }

    public func count() async throws(AdapterError) -> Int {
        try check()
        return points.count
    }

    public func close() async {
        isClosed = true
    }

    public static func cosine(_ lhs: [Float], _ rhs: [Float]) -> Float {
        guard lhs.count == rhs.count, !lhs.isEmpty else { return 0 }
        var dot: Float = 0
        var lhsNorm: Float = 0
        var rhsNorm: Float = 0
        for index in lhs.indices {
            dot += lhs[index] * rhs[index]
            lhsNorm += lhs[index] * lhs[index]
            rhsNorm += rhs[index] * rhs[index]
        }
        let denominator = lhsNorm.squareRoot() * rhsNorm.squareRoot()
        return denominator == 0 ? 0 : dot / denominator
    }

    private func check() throws(AdapterError) {
        if isClosed { throw .vectorStore("Store is closed") }
        if let failure { throw failure }
    }
}

/// Embedding provider that returns scripted results in order, then a default vector.
public actor FakeEmbeddingProvider: EmbeddingProviding {
    public private(set) var embedCount = 0
    private var scripted: [Result<[Float], AdapterError>]
    private let defaultVector: [Float]

    public init(scripted: [Result<[Float], AdapterError>] = [], defaultVector: [Float] = [1, 0, 0]) {
        self.scripted = scripted
        self.defaultVector = defaultVector
    }

    public func embed(image: CGImage) async throws(AdapterError) -> [Float] {
        embedCount += 1
        guard !scripted.isEmpty else { return defaultVector }
        return try scripted.removeFirst().get()
    }
}

public enum FakeImages {
    /// A 1×1 opaque image for adapter fakes.
    public static func onePixel() -> CGImage? {
        let context = CGContext(
            data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )
        context?.setFillColor(CGColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1))
        context?.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        return context?.makeImage()
    }
}
