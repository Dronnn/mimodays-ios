import Foundation
import UserNotifications

/// Local notifications through `UNUserNotificationCenter`. The app only schedules surprises,
/// so every pending request is one.
public struct SystemNotificationScheduler: NotificationScheduler {
    public init() {}

    public func pending() async -> [SurpriseNotification] {
        let requests = await UNUserNotificationCenter.current().pendingNotificationRequests()
        return requests.compactMap { request in
            guard let date = (request.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate() else { return nil }
            return SurpriseNotification(id: request.identifier, fireDate: date, title: request.content.title, body: request.content.body)
        }
        .sorted { $0.fireDate < $1.fireDate }
    }

    public func schedule(_ notification: SurpriseNotification) async throws {
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body
        content.sound = .default
        content.userInfo = [SurpriseNotification.promptIDKey: notification.id]
        // Components carry the time zone, so the request fires at this exact instant; the coordinator
        // re-plans when the device's time zone changes.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let components = calendar.dateComponents(
            [.timeZone, .year, .month, .day, .hour, .minute, .second], from: notification.fireDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        try await UNUserNotificationCenter.current()
            .add(UNNotificationRequest(identifier: notification.id, content: content, trigger: trigger))
    }

    public func cancel(ids: [String]) async {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }
}
