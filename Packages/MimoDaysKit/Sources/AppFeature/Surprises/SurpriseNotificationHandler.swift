import Foundation
import UserNotifications

/// The notification center's delegate, set at launch so a tap that starts the app is not lost.
/// Taps wait here until the UI starts listening.
@MainActor
final class SurpriseNotificationHandler: NSObject, UNUserNotificationCenterDelegate {
    private var waiting: UUID?
    private var onOpen: ((UUID) -> Void)?
    /// P8.7: "Remind me later" pressed on a surprise; set at launch, as it runs with the app in the background.
    var remindLater: ((UUID) async -> Void)?

    /// The surprise's "Remind me later", in the app's language; registered at launch and when the language changes.
    static func registerActions() {
        let action = UNNotificationAction(
            identifier: SurpriseCoordinator.remindLaterAction, title: String(appLocalized: SurpriseCoordinator.remindLaterTitle), options: []
        )
        let category = UNNotificationCategory(identifier: SurpriseCoordinator.remindLaterCategory, actions: [action], intentIdentifiers: [])
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

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
        let promptID: UUID? = if case let .capture(id?) = AppRouter.route(fromNotification: response.notification.request.content.userInfo) {
            id
        } else {
            nil
        }
        let action = response.actionIdentifier
        Task { @MainActor in
            if let promptID {
                if action == UNNotificationDefaultActionIdentifier {
                    deliver(promptID)
                } else if action == SurpriseCoordinator.remindLaterAction {
                    await remindLater?(promptID)
                }
            }
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
