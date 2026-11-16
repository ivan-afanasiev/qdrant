#if os(iOS)
import Foundation
import UserNotifications
import SweepDomain

/// UserNotifications adapter for "photos are ready for review". Texts are supplied by the
/// presentation layer so they can be localized there.
public struct UserNotificationReviewNotifier: ReviewReadyNotifying {
    /// Reusing one identifier replaces an undelivered notification instead of stacking them.
    public static let requestIdentifier = "com.qdrant.edge.PhotoSweep.reviewReady"

    private let title: String
    private let body: @Sendable (_ unavailableCount: Int) -> String

    public init(title: String, body: @escaping @Sendable (_ unavailableCount: Int) -> String) {
        self.title = title
        self.body = body
    }

    public func permission() async -> NotificationPermission {
        switch await UNUserNotificationCenter.current().notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral: .authorized
        case .denied: .denied
        case .notDetermined: .notDetermined
        @unknown default: .denied
        }
    }

    /// Asks for permission; the presentation layer decides when (step 9).
    public func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    public func postReviewReady(unavailableCount: Int) async throws {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body(unavailableCount)
        let request = UNNotificationRequest(identifier: Self.requestIdentifier, content: content, trigger: nil)
        try await UNUserNotificationCenter.current().add(request)
    }
}
#endif
