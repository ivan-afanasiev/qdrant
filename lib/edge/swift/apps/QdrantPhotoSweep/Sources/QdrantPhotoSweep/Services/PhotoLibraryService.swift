import CoreGraphics
import Photos

final class PhotoLibraryService: PhotoLibraryProviding, @unchecked Sendable {
    func requestAuthorization() async throws(AppError) {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        switch status {
        case .authorized, .limited:
            return
        case .denied:
            throw .authorization(L10n.photoAccessDenied)
        case .restricted:
            throw .authorization(L10n.photoAccessRestricted)
        case .notDetermined:
            throw .authorization(L10n.photoAccessNotDetermined)
        @unknown default:
            throw .authorization(L10n.photoAccessUnknown)
        }
    }

    func fetchAssets(in dateRange: DateRange) async throws(AppError) -> [PhotoAsset] {
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

    func countAssets(in dateRange: DateRange) async throws(AppError) -> Int {
        let options = PHFetchOptions()
        options.predicate = datePredicate(for: dateRange)
        let result = PHAsset.fetchAssets(with: .image, options: options)
        return result.count
    }

    func loadThumbnail(for asset: PhotoAsset, size: CGSize) async throws(AppError) -> CGImage {
        guard let phAsset = phAsset(for: asset.localIdentifier) else {
            throw .photoLibrary("Asset not found: \(asset.localIdentifier)")
        }
        return try await loadHighQualityCGImage(for: phAsset, targetSize: size)
    }

    func loadFullImage(for asset: PhotoAsset) async throws(AppError) -> CGImage {
        guard let phAsset = phAsset(for: asset.localIdentifier) else {
            throw .photoLibrary("Asset not found: \(asset.localIdentifier)")
        }
        let size = CGSize(width: phAsset.pixelWidth, height: phAsset.pixelHeight)
        return try await loadCGImage(for: phAsset, targetSize: size)
    }

    func deleteAssets(_ identifiers: [String]) async throws(AppError) {
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
            throw .deletion("Failed to delete photos: \(error.localizedDescription)")
        }
    }

    // MARK: - Private

    private func datePredicate(for dateRange: DateRange) -> NSPredicate {
        NSPredicate(
            format: "creationDate == nil OR (creationDate >= %@ AND creationDate <= %@)",
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
