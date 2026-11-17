#if os(iOS)
import SweepDomain
import CoreGraphics
import Photos

public final class PhotoLibraryService: PhotoLibraryProviding, @unchecked Sendable {
    public init() {}
    public func requestAuthorization() async throws(AdapterError) {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        switch status {
        case .authorized, .limited:
            return
        case .denied:
            throw .authorization("Photo access denied")
        case .restricted:
            throw .authorization("Photo access restricted")
        case .notDetermined:
            throw .authorization("Photo access not determined")
        @unknown default:
            throw .authorization("Unknown photo authorization status")
        }
    }

    public func accessScope() async -> PhotoAccessScope {
        switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
        case .authorized: .full
        case .limited: .limited
        default: .none
        }
    }

    public func assets(withIdentifiers identifiers: [String]) async throws(AdapterError) -> [PhotoAsset] {
        let result = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
        var assets: [PhotoAsset] = []
        assets.reserveCapacity(result.count)
        result.enumerateObjects { phAsset, _, _ in
            assets.append(phAsset.toPhotoAsset())
        }
        return assets
    }

    public func fetchAssets(in dateRange: DateRange) async throws(AdapterError) -> [PhotoAsset] {
        let options = PHFetchOptions()
        options.predicate = datePredicate(for: dateRange)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

        let result = PHAsset.fetchAssets(with: .image, options: options)
        var assets: [PhotoAsset] = []
        assets.reserveCapacity(result.count)
        result.enumerateObjects { phAsset, _, _ in
            assets.append(phAsset.toPhotoAsset())
        }
        return assets
    }

    public func countAssets(in dateRange: DateRange) async throws(AdapterError) -> Int {
        let options = PHFetchOptions()
        options.predicate = datePredicate(for: dateRange)
        let result = PHAsset.fetchAssets(with: .image, options: options)
        return result.count
    }

    public func loadThumbnail(for asset: PhotoAsset, size: CGSize) async throws(AdapterError) -> CGImage {
        guard let phAsset = phAsset(for: asset.localIdentifier) else {
            throw .photoLibrary("Asset not found: \(asset.localIdentifier)")
        }
        return try await loadCGImage(for: phAsset, targetSize: size)
    }

    public func loadFullImage(for asset: PhotoAsset) async throws(AdapterError) -> CGImage {
        guard let phAsset = phAsset(for: asset.localIdentifier) else {
            throw .photoLibrary("Asset not found: \(asset.localIdentifier)")
        }
        return try await loadOriginalCGImage(for: phAsset)
    }

    public func loadDisplayImage(for asset: PhotoAsset, maxPixels: Int) async throws(AdapterError) -> CGImage {
        guard let phAsset = phAsset(for: asset.localIdentifier) else {
            throw .photoLibrary("Asset not found: \(asset.localIdentifier)")
        }
        let side = CGFloat(max(1, maxPixels))
        return try await loadHighQualityCGImage(for: phAsset, targetSize: CGSize(width: side, height: side))
    }

    public func deleteAssets(_ identifiers: [String]) async throws(AdapterError) {
        let fetchResult = PHAsset.fetchAssets(
            withLocalIdentifiers: identifiers,
            options: nil
        )
        guard fetchResult.count > 0 else { return }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                let assets = NSMutableArray()
                fetchResult.enumerateObjects { asset, _, _ in
                    assets.add(asset)
                }
                PHAssetChangeRequest.deleteAssets(assets)
            }
        } catch {
            if (error as? PHPhotosError)?.code == .userCancelled {
                throw .deletionDeclined
            }
            throw .deletion("Failed to delete photos: \(error.localizedDescription)")
        }
    }

    // MARK: - Private

    private func datePredicate(for dateRange: DateRange) -> NSPredicate {
        NSPredicate(
            format: "creationDate >= %@ AND creationDate <= %@",
            dateRange.start as NSDate,
            dateRange.end as NSDate
        )
    }

    private func phAsset(for localIdentifier: String) -> PHAsset? {
        let result = PHAsset.fetchAssets(
            withLocalIdentifiers: [localIdentifier],
            options: nil
        )
        return result.firstObject
    }
}

#endif
