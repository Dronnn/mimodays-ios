import Foundation
import UserNotifications

/// The notification center's delegate, set at launch so a tap that starts the app is not lost.
/// Taps wait here until the UI starts listening.
@MainActor
final class SurpriseNotificationHandler: NSObject, UNUserNotificationCenterDelegate {
    private var waiting: UUID?
    private var onOpen: ((UUID) -> Void)?

    func listen(_ handler: @escaping (UUID) -> Void) {
        onOpen = handler
        if let waiting {
            self.waiting = nil
            handler(waiting)
        }
    }

    /// A tap on the surprise for `promptID`.
    func deliver(_ promptID: UUID) {
        if let onOpen { onOpen(promptID) } else { waiting = promptID }
    }

    /// The completion-handler form, called back on the main thread: with the async form, Swift calls the system's
    /// handler from a background thread and UIKit stops the app (tapping a surprise crashed it on an iPhone 16 Pro,
    /// 2026-11-17).
    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping @Sendable () -> Void
    ) {
        let promptID: UUID? = if response.actionIdentifier == UNNotificationDefaultActionIdentifier,
                                 case let .capture(id?) = AppRouter.route(fromNotification: response.notification.request.content.userInfo) {
            id
        } else {
            nil
        }
        Task { @MainActor in
            if let promptID { deliver(promptID) }
            completionHandler()
        }
    }

    /// A surprise that arrives while the app is open still shows, so it can be tapped.
    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter, willPresent _: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
