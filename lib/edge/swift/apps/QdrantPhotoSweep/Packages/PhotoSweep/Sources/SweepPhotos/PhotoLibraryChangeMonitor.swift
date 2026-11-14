#if os(iOS)
import Foundation
import Photos
import SweepDomain

/// Forwards Photos change notifications to every active stream. Each stream keeps at most
/// one pending element, so a burst of changes becomes a single reconciliation request.
public final class PhotoLibraryChangeMonitor: NSObject, PHPhotoLibraryChangeObserver, PhotoLibraryChangeObserving, @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [UUID: AsyncStream<Void>.Continuation] = [:]
    private var isRegistered = false

    override public init() {
        super.init()
    }

    deinit {
        if isRegistered {
            PHPhotoLibrary.shared().unregisterChangeObserver(self)
        }
    }

    public func libraryChanges() -> AsyncStream<Void> {
        let (stream, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let id = UUID()
        continuation.onTermination = { [weak self] _ in
            self?.remove(id)
        }
        lock.lock()
        continuations[id] = continuation
        let needsRegistration = !isRegistered
        isRegistered = true
        lock.unlock()
        // Registration is deferred until someone listens, after authorization has been requested.
        if needsRegistration {
            PHPhotoLibrary.shared().register(self)
        }
        return stream
    }

    public func photoLibraryDidChange(_ changeInstance: PHChange) {
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
#endif
