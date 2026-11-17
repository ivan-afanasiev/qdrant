import CoreGraphics
import Foundation
import SweepDomain

/// Fetches photos in scope and registers their identity and content revision.
public struct ReconcilePhotoLibrary: Sendable {
    public struct Result: Sendable {
        public let records: [AssetRecord]
        public let photos: [AssetID: PhotoAsset]
    }

    private let library: any PhotoLibraryProviding
    private let assets: any AssetRepository

    public init(library: any PhotoLibraryProviding, assets: any AssetRepository) {
        self.library = library
        self.assets = assets
    }

    static let registrationChunk = 500

    /// - Parameter onProgress: photos registered so far and the total, after the fetch and
    ///   after every chunk.
    public func execute(
        scope: DateRange,
        onProgress: @Sendable (_ done: Int, _ total: Int) async -> Void = { _, _ in }
    ) async throws(VectorizationFailure) -> Result {
        let photos: [PhotoAsset]
        do {
            photos = try await library.fetchAssets(in: scope)
        } catch {
            throw Self.classify(error)
        }
        let discovered = photos.map {
            DiscoveredAsset(id: AssetID($0.localIdentifier), creationDate: $0.creationDate, contentRevision: $0.contentRevision)
        }
        do {
            // Registered in chunks so other metadata work, such as saving a person's
            // choices, is not held up behind one call covering the whole library.
            var records: [AssetRecord] = []
            records.reserveCapacity(discovered.count)
            await onProgress(0, discovered.count)
            for start in stride(from: 0, to: discovered.count, by: Self.registrationChunk) {
                let chunk = Array(discovered[start..<min(start + Self.registrationChunk, discovered.count)])
                records += try await assets.register(chunk)
                await onProgress(records.count, discovered.count)
            }
            let byID = Dictionary(photos.map { (AssetID($0.localIdentifier), $0) }, uniquingKeysWith: { first, _ in first })
            return Result(records: records, photos: byID)
        } catch {
            throw .systemic("Metadata store: \(error)")
        }
    }

    static func classify(_ error: AdapterError) -> VectorizationFailure {
        switch error {
        case .authorization: .authorization
        case .photoLibrary(let message): .transient(message)
        default: .systemic(String(describing: error))
        }
    }
}

/// Loads a thumbnail and computes its feature print. Never requests full resolution.
public struct VectorizePhoto: Sendable {
    private let library: any PhotoLibraryProviding
    private let embedder: any EmbeddingProviding
    private let thumbnailPixels: Int

    public init(library: any PhotoLibraryProviding, embedder: any EmbeddingProviding, thumbnailPixels: Int) {
        self.library = library
        self.embedder = embedder
        self.thumbnailPixels = thumbnailPixels
    }

    public func execute(_ photo: PhotoAsset, expectedDimensions: Int) async throws(VectorizationFailure) -> [Float] {
        let image: CGImage
        do {
            image = try await library.loadThumbnail(for: photo, size: CGSize(width: thumbnailPixels, height: thumbnailPixels))
        } catch {
            switch error {
            case .authorization: throw .authorization
            case .photoLibrary(let message): throw .assetUnavailable(message)
            default: throw .transient(String(describing: error))
            }
        }
        let vector: [Float]
        do {
            vector = try await embedder.embed(image: image)
        } catch {
            // A failing image is treated as this photo's problem; the executor's consecutive-
            // deferral breaker catches a model that fails for every photo.
            switch error {
            case .embedding(let message): throw .assetUnavailable(message)
            default: throw .transient(String(describing: error))
            }
        }
        guard vector.count == expectedDimensions else {
            throw .incompatibleEmbedding("Expected \(expectedDimensions) dimensions, got \(vector.count)")
        }
        return vector
    }
}
