import CoreGraphics
import Foundation
import SweepDomain

#if os(iOS)
import SweepDesignSystem
import SweepEmbeddings
import SweepPhotos
import SweepSystem

/// iOS adapters.
enum LivePlatform {
    static func library() -> any PhotoLibraryProviding { PhotoLibraryService() }
    static func libraryChanges() -> any PhotoLibraryChangeObserving { PhotoLibraryChangeMonitor() }
    static func embedder() -> any EmbeddingProviding & EmbeddingModelDescribing { VisionEmbeddingService() }

    static func scheduler() -> any BackgroundExecutionScheduling {
        BackgroundTaskScheduler(
            continuedTitle: String(localized: L10n.backgroundTitle),
            continuedSubtitle: String(localized: L10n.backgroundSubtitle)
        )
    }

    static func notifier() -> any ReviewReadyNotifying {
        UserNotificationReviewNotifier(title: String(localized: L10n.reviewReadyTitle)) { unavailable in
            unavailable == 0
                ? String(localized: L10n.reviewReadyBody)
                : L10n.reviewReadyBodyWithUnavailable(unavailable)
        }
    }
}
#else
/// Host (macOS) stand-ins: the package's macOS platform exists only for host-side tests,
/// so live Photos, Vision and background execution are unavailable there.
enum LivePlatform {
    static func library() -> any PhotoLibraryProviding { UnavailablePhotoLibrary() }
    static func libraryChanges() -> any PhotoLibraryChangeObserving { NoLibraryChanges() }
    static func embedder() -> any EmbeddingProviding & EmbeddingModelDescribing { UnavailableEmbedder() }
    static func scheduler() -> any BackgroundExecutionScheduling { NoBackgroundExecution() }
    static func notifier() -> any ReviewReadyNotifying { NoNotifications() }
}

private struct UnavailablePhotoLibrary: PhotoLibraryProviding {
    func requestAuthorization() async throws(AdapterError) { throw .authorization("Photos is unavailable on this platform") }
    func accessScope() async -> PhotoAccessScope { .none }
    func assets(withIdentifiers identifiers: [String]) async throws(AdapterError) -> [PhotoAsset] { [] }
    func fetchAssets(in dateRange: DateRange) async throws(AdapterError) -> [PhotoAsset] { [] }
    func countAssets(in dateRange: DateRange) async throws(AdapterError) -> Int { 0 }
    func loadThumbnail(for asset: PhotoAsset, size: CGSize) async throws(AdapterError) -> CGImage { throw .photoLibrary("Unavailable") }
    func loadFullImage(for asset: PhotoAsset) async throws(AdapterError) -> CGImage { throw .photoLibrary("Unavailable") }
    func loadDisplayImage(for asset: PhotoAsset, maxPixels: Int) async throws(AdapterError) -> CGImage { throw .photoLibrary("Unavailable") }
    func deleteAssets(_ identifiers: [String]) async throws(AdapterError) { throw .deletion("Unavailable") }
}

private struct NoLibraryChanges: PhotoLibraryChangeObserving {
    func libraryChanges() -> AsyncStream<Void> { AsyncStream { $0.finish() } }
}

private struct UnavailableEmbedder: EmbeddingProviding, EmbeddingModelDescribing {
    func embed(image: CGImage) async throws(AdapterError) -> [Float] { throw .embedding("Vision is unavailable on this platform") }
    func modelDescriptor() async throws(AdapterError) -> EmbeddingModelDescriptor { throw .embedding("Vision is unavailable on this platform") }
}

private struct NoBackgroundExecution: BackgroundExecutionScheduling {
    func requestContinuedProcessing() async -> Bool { false }
    func scheduleProcessing() async -> Bool { false }
    func beginGraceWindow() async -> (any ExecutionWindow)? { nil }
}

private struct NoNotifications: ReviewReadyNotifying {
    func permission() async -> NotificationPermission { .denied }
    func requestPermission() async -> Bool { false }
    func postReviewReady(unavailableCount: Int) async throws {}
}
#endif
