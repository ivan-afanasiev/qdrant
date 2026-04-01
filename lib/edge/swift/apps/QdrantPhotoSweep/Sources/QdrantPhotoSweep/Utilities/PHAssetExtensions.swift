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
    options.deliveryMode = .fastFormat
    options.resizeMode = .fast
    options.isSynchronous = false
    options.isNetworkAccessAllowed = true

    do {
        return try await withCheckedThrowingContinuation { continuation in
            let resumed = OSAllocatedUnfairLock(initialState: false)
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: options
            ) { image, info in
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                guard !isDegraded else { return }

                let alreadyResumed = resumed.withLock { state -> Bool in
                    guard !state else { return true }
                    state = true
                    return false
                }
                guard !alreadyResumed else { return }

                if let error = info?[PHImageErrorKey] as? Error {
                    continuation.resume(throwing: AppError.photoLibrary("Image load failed: \(error.localizedDescription)"))
                    return
                }

                guard let cgImage = image?.cgImage else {
                    continuation.resume(throwing: AppError.photoLibrary("Failed to load image"))
                    return
                }
                continuation.resume(returning: cgImage)
            }
        }
    } catch let error as AppError {
        throw error
    } catch {
        throw .photoLibrary("Image load failed: \(error.localizedDescription)")
    }
}

func loadHighQualityCGImage(for asset: PHAsset, targetSize: CGSize) async throws(AppError) -> CGImage {
    let options = PHImageRequestOptions()
    options.deliveryMode = .highQualityFormat
    options.resizeMode = .exact
    options.isSynchronous = false
    options.isNetworkAccessAllowed = true

    do {
        return try await withCheckedThrowingContinuation { continuation in
            let resumed = OSAllocatedUnfairLock(initialState: false)
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFit,
                options: options
            ) { image, info in
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                guard !isDegraded else { return }

                let alreadyResumed = resumed.withLock { state -> Bool in
                    guard !state else { return true }
                    state = true
                    return false
                }
                guard !alreadyResumed else { return }

                if let error = info?[PHImageErrorKey] as? Error {
                    continuation.resume(throwing: AppError.photoLibrary("Image load failed: \(error.localizedDescription)"))
                    return
                }

                guard let cgImage = image?.cgImage else {
                    continuation.resume(throwing: AppError.photoLibrary("Failed to load full-res image"))
                    return
                }
                continuation.resume(returning: cgImage)
            }
        }
    } catch let error as AppError {
        throw error
    } catch {
        throw .photoLibrary("Image load failed: \(error.localizedDescription)")
    }
}
