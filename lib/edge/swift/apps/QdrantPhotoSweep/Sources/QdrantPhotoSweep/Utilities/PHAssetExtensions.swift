import os
import Photos
import UIKit

extension PHAsset {
    func toPhotoAsset() -> PhotoAsset {
        PhotoAsset(
            id: localIdentifier,
            localIdentifier: localIdentifier,
            creationDate: creationDate,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            fileSize: nil
        )
    }
}

func loadCGImage(for asset: PHAsset, targetSize: CGSize) async throws(AppError) -> CGImage {
    let options = PHImageRequestOptions()
    options.deliveryMode = .highQualityFormat
    options.resizeMode = .exact
    options.isSynchronous = false
    options.isNetworkAccessAllowed = true
    return try await requestCGImage(
        for: asset,
        targetSize: targetSize,
        contentMode: .aspectFill,
        options: options,
        failureMessage: "Failed to load image"
    )
}

func loadHighQualityCGImage(for asset: PHAsset, targetSize: CGSize) async throws(AppError) -> CGImage {
    let options = PHImageRequestOptions()
    options.deliveryMode = .highQualityFormat
    options.resizeMode = .exact
    options.isSynchronous = false
    options.isNetworkAccessAllowed = true

    return try await requestCGImage(
        for: asset,
        targetSize: targetSize,
        contentMode: .aspectFit,
        options: options,
        failureMessage: "Failed to load full-res image"
    )
}

private func requestCGImage(
    for asset: PHAsset,
    targetSize: CGSize,
    contentMode: PHImageContentMode,
    options: PHImageRequestOptions,
    failureMessage: String
) async throws(AppError) -> CGImage {
    let manager = PHImageManager.default()
    let resumed = OSAllocatedUnfairLock(initialState: false)
    let requestIdLock = OSAllocatedUnfairLock(initialState: PHInvalidImageRequestID)

    do {
        return try await withThrowingTaskGroup(of: CGImage.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { continuation in
                    let requestId = manager.requestImage(
                        for: asset,
                        targetSize: targetSize,
                        contentMode: contentMode,
                        options: options
                    ) { image, info in
                        let alreadyResumed = resumed.withLock { state -> Bool in
                            guard !state else { return true }
                            let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                            if isDegraded {
                                return true
                            }
                            state = true
                            return false
                        }
                        guard !alreadyResumed else { return }

                        if let cancelled = info?[PHImageCancelledKey] as? Bool, cancelled {
                            continuation.resume(throwing: AppError.photoLibrary("Image request was cancelled"))
                            return
                        }

                        if let error = info?[PHImageErrorKey] as? Error {
                            continuation.resume(throwing: AppError.photoLibrary("Image load failed: \(error.localizedDescription)"))
                            return
                        }

                        guard let cgImage = image?.cgImage else {
                            continuation.resume(throwing: AppError.photoLibrary(failureMessage))
                            return
                        }
                        continuation.resume(returning: cgImage)
                    }
                    requestIdLock.withLock { $0 = requestId }
                }
            }

            group.addTask {
                try await Task.sleep(for: .seconds(20))
                throw AppError.photoLibrary("Timed out while loading image from Photos")
            }

            guard let first = try await group.next() else {
                throw AppError.photoLibrary(failureMessage)
            }
            group.cancelAll()
            let requestId = requestIdLock.withLock { $0 }
            if requestId != PHInvalidImageRequestID {
                manager.cancelImageRequest(requestId)
            }
            return first
        }
    } catch let error as AppError {
        let requestId = requestIdLock.withLock { $0 }
        if requestId != PHInvalidImageRequestID {
            manager.cancelImageRequest(requestId)
        }
        throw error
    } catch {
        let requestId = requestIdLock.withLock { $0 }
        if requestId != PHInvalidImageRequestID {
            manager.cancelImageRequest(requestId)
        }
        throw .photoLibrary("Image load failed: \(error.localizedDescription)")
    }
}
