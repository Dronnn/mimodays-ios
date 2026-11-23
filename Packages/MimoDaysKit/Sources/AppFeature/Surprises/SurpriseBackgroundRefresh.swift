import BackgroundTasks
import Foundation
import os

/// rev-app 10: now and then iOS wakes MimoDays in the background, so the surprise plan keeps reaching its two weeks
/// ahead for someone who doesn't open the app for a while. The identifier is in the app's
/// `BGTaskSchedulerPermittedIdentifiers`; the app's scene runs it (`AppDependencies.refreshSurprisesInBackground`).
public enum SurpriseBackgroundRefresh {
    public static let identifier = "com.mrmaier.MimoDays.surprises"
    /// The plan reaches 14 days ahead: twice a day at most is plenty, and iOS picks the moment anyway.
    static let interval: TimeInterval = 12 * 60 * 60

    private static let logger = Logger(subsystem: "MimoDays", category: "Surprises")

    static func request(now: Date) -> BGAppRefreshTaskRequest {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = now.addingTimeInterval(interval)
        return request
    }

    /// Asks for the next wake-up; a newer request replaces the one before. The simulator refuses: nothing to do.
    static func schedule(now: Date = .now) {
        do {
            try BGTaskScheduler.shared.submit(request(now: now))
        } catch {
            logger.info("No background refresh asked for: \(error.localizedDescription, privacy: .public)")
        }
    }
}
