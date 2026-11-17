import CoreGraphics
import Foundation
import SweepDomain

/// In-memory photo library that records every image request, so tests can prove
/// thumbnails are used for processing and full resolution only for preview.
public actor FakePhotoLibrary: PhotoLibraryProviding {
    public enum ImageRequest: Equatable, Sendable {
        case thumbnail(assetID: String, size: CGSize)
        case fullResolution(assetID: String)
        case display(assetID: String, maxPixels: Int)
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

    public func setAssets(_ assets: [PhotoAsset]) {
        self.assets = assets
    }

    public var scope: PhotoAccessScope = .full

    public func requestAuthorization() async throws(AdapterError) {
        if let authorizationError { throw authorizationError }
    }

    public func setAccessScope(_ scope: PhotoAccessScope) {
        self.scope = scope
    }

    public func accessScope() async -> PhotoAccessScope {
        scope
    }

    public func assets(withIdentifiers identifiers: [String]) async throws(AdapterError) -> [PhotoAsset] {
        if let authorizationError { throw authorizationError }
        let wanted = Set(identifiers)
        return assets.filter { wanted.contains($0.localIdentifier) }
    }

    public private(set) var fetchCount = 0
    private var fetchWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    public func fetchAssets(in dateRange: DateRange) async throws(AdapterError) -> [PhotoAsset] {
        if let authorizationError { throw authorizationError }
        fetchCount += 1
        let ready = fetchWaiters.filter { $0.count <= fetchCount }
        fetchWaiters.removeAll { $0.count <= fetchCount }
        ready.forEach { $0.continuation.resume() }
        return assets.filter { dateRange.contains($0.creationDate) }
    }

    /// Suspends until the library has been fetched at least `count` times, so tests can
    /// wait for an automatically triggered pass without timing.
    public func waitForFetches(_ count: Int) async {
        guard fetchCount < count else { return }
        await withCheckedContinuation { continuation in
            fetchWaiters.append((count, continuation))
        }
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

    public func loadDisplayImage(for asset: PhotoAsset, maxPixels: Int) async throws(AdapterError) -> CGImage {
        imageRequests.append(.display(assetID: asset.id, maxPixels: maxPixels))
        return try image(for: asset)
    }

    /// When true, the deletion happens but the call still reports `deletionError`.
    public var deletesBeforeFailing = false

    public func setDeletesBeforeFailing(_ value: Bool) {
        deletesBeforeFailing = value
    }

    public func deleteAssets(_ identifiers: [String]) async throws(AdapterError) {
        if let deletionError, !deletesBeforeFailing { throw deletionError }
        deletedIdentifiers.append(identifiers)
        let deleted = Set(identifiers)
        assets.removeAll { deleted.contains($0.localIdentifier) }
        if let deletionError { throw deletionError }
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
    /// Number of paged neighborhood queries, for asserting lazy (not whole-library) work.
    public private(set) var searchPageCount = 0
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

    public func searchPage(
        vector: [Float],
        threshold: Float,
        filter: VectorSearchFilter?,
        offset: Int,
        limit: Int
    ) async throws(AdapterError) -> [ScoredResult] {
        try check()
        searchPageCount += 1
        var matches: [ScoredResult] = []
        for point in points.values {
            if let filter {
                guard let created = VectorPayload.decode(point.payloadJson)?.created,
                      filter.creationRange.contains(created) else { continue }
            }
            let score = Self.cosine(vector, point.vector)
            guard score >= threshold else { continue }
            matches.append(ScoredResult(id: point.id, score: score, payloadJson: point.payloadJson, vectorJson: nil))
        }
        matches.sort { lhs, rhs in
            lhs.score == rhs.score ? lhs.id < rhs.id : lhs.score > rhs.score
        }
        guard offset < matches.count else { return [] }
        return Array(matches[offset..<min(offset + limit, matches.count)])
    }

    public func vector(id: String) async throws(AdapterError) -> [Float]? {
        try check()
        return points[id]?.vector
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
public actor FakeEmbeddingProvider: EmbeddingProviding, EmbeddingModelDescribing {
    public private(set) var embedCount = 0
    private var scripted: [Result<[Float], AdapterError>]
    private var defaultVector: [Float]
    private var descriptor: EmbeddingModelDescriptor

    public init(scripted: [Result<[Float], AdapterError>] = [], defaultVector: [Float] = [1, 0, 0], modelRevision: Int = 1) {
        self.scripted = scripted
        self.defaultVector = defaultVector
        self.descriptor = EmbeddingModelDescriptor(model: "fake", revision: modelRevision, dimensions: defaultVector.count)
    }

    public func modelDescriptor() async throws(AdapterError) -> EmbeddingModelDescriptor {
        descriptor
    }

    /// Simulates an OS update that changes the model.
    public func changeModel(revision: Int, defaultVector: [Float]) {
        self.defaultVector = defaultVector
        descriptor = EmbeddingModelDescriptor(model: "fake", revision: revision, dimensions: defaultVector.count)
    }

    public func script(_ results: [Result<[Float], AdapterError>]) {
        scripted.append(contentsOf: results)
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

/// Vector store provider handing out one in-memory store per generation.
public actor FakeVectorStoreProvider: VectorStoreProviding {
    public private(set) var stores: [Int: FakeVectorStore] = [:]
    public private(set) var removedBelow: [Int] = []
    private var dimensions: [Int: Int] = [:]

    public init() {}

    public func store(for generation: IndexGeneration, dimensions: Int) async throws(AdapterError) -> any VectorStoring {
        try fakeStore(for: generation, dimensions: dimensions)
    }

    /// Typed access for assertions.
    public func fakeStore(for generation: IndexGeneration, dimensions: Int) throws(AdapterError) -> FakeVectorStore {
        if let existing = stores[generation.rawValue] {
            guard self.dimensions[generation.rawValue] == dimensions else {
                throw .vectorStore("Dimension mismatch for generation \(generation.rawValue)")
            }
            return existing
        }
        let store = FakeVectorStore()
        stores[generation.rawValue] = store
        self.dimensions[generation.rawValue] = dimensions
        return store
    }

    public func removeStores(olderThan generation: IndexGeneration) async {
        removedBelow.append(generation.rawValue)
        for key in stores.keys where key < generation.rawValue {
            stores[key] = nil
            dimensions[key] = nil
        }
    }
}

/// Manually triggered library change notifications.
public final class FakePhotoLibraryChanges: PhotoLibraryChangeObserving, @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [UUID: AsyncStream<Void>.Continuation] = [:]

    public init() {}

    public var observerCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return continuations.count
    }

    public func libraryChanges() -> AsyncStream<Void> {
        let (stream, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let id = UUID()
        continuation.onTermination = { [weak self] _ in
            self?.remove(id)
        }
        lock.lock()
        continuations[id] = continuation
        lock.unlock()
        return stream
    }

    public func send() {
        lock.lock()
        let active = Array(continuations.values)
        lock.unlock()
        for continuation in active {
            continuation.yield()
        }
    }

    private func remove(_ id: UUID) {
        lock.lock()
        continuations[id] = nil
        lock.unlock()
    }
}
