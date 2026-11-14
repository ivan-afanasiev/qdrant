#if os(iOS)
import SweepDomain
import os
import Photos
import UIKit

public extension PHAsset {
    func toPhotoAsset() -> PhotoAsset {
        PhotoAsset(
            id: localIdentifier,
            localIdentifier: localIdentifier,
            creationDate: creationDate,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            fileSize: nil,
            modificationDate: modificationDate
        )
    }
}

/// Serializes continuation completion against cancellation and request-ID publication.
final class PhotoImageRequest: @unchecked Sendable {
    private struct State {
        var continuation: CheckedContinuation<CGImage, Error>?
        var requestId: PHImageRequestID?
        var cancelled = false
    }
    private let state = OSAllocatedUnfairLock(initialState: State())

    func install(_ continuation: CheckedContinuation<CGImage, Error>) -> Bool {
        let cancelled = state.withLock { state in
            if state.cancelled { return true }
            state.continuation = continuation
            return false
        }
        if cancelled { continuation.resume(throwing: CancellationError()) }
        return !cancelled
    }

    func setRequestId(_ id: PHImageRequestID) {
        let cancelled = state.withLock { state in
            state.requestId = id
            return state.cancelled
        }
        if cancelled { PHImageManager.default().cancelImageRequest(id) }
    }

    func finish(_ result: Result<CGImage, Error>) {
        let continuation = state.withLock { state in
            let continuation = state.continuation
            state.continuation = nil
            return continuation
        }
        continuation?.resume(with: result)
    }

    func cancel() {
        let pending = state.withLock { state in
            state.cancelled = true
            let pending = (state.continuation, state.requestId)
            state.continuation = nil
            return pending
        }
        pending.0?.resume(throwing: CancellationError())
        if let id = pending.1 { PHImageManager.default().cancelImageRequest(id) }
    }
}

public func loadCGImage(for asset: PHAsset, targetSize: CGSize) async throws(AdapterError) -> CGImage {
    try await requestCGImage(for: asset, targetSize: targetSize, highQuality: false)
}

public func loadHighQualityCGImage(for asset: PHAsset, targetSize: CGSize) async throws(AdapterError) -> CGImage {
    try await requestCGImage(for: asset, targetSize: targetSize, highQuality: true)
}

private func requestCGImage(
    for asset: PHAsset, targetSize: CGSize, highQuality: Bool
) async throws(AdapterError) -> CGImage {
    let request = PhotoImageRequest()
    let options = PHImageRequestOptions()
    options.deliveryMode = highQuality ? .highQualityFormat : .fastFormat
    options.resizeMode = highQuality ? .exact : .fast
    options.isSynchronous = false
    options.isNetworkAccessAllowed = true
    do {
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                guard request.install(continuation) else { return }
                let id = PHImageManager.default().requestImage(
                    for: asset, targetSize: targetSize,
                    contentMode: highQuality ? .aspectFit : .aspectFill, options: options
                ) { image, info in
                    if (info?[PHImageCancelledKey] as? Bool) == true {
                        request.finish(.failure(CancellationError()))
                    } else if let error = info?[PHImageErrorKey] as? Error {
                        request.finish(.failure(error))
                    } else if (info?[PHImageResultIsDegradedKey] as? Bool) != true {
                        if let cgImage = image?.cgImage {
                            request.finish(.success(cgImage))
                        } else {
                            request.finish(.failure(AdapterError.photoLibrary("Failed to load image")))
                        }
                    }
                }
                request.setRequestId(id)
            }
        } onCancel: {
            request.cancel()
        }
    } catch {
        // Callers use Task.isCancelled to distinguish cancellation with this typed-throws API.
        throw error as? AdapterError ?? .photoLibrary(error.localizedDescription)
    }
}

#endif
