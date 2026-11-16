#if DEBUG
import Core
import Foundation
import Persistence
import UserNotifications

/// `-demo-footage <folder>` (debug builds, website recordings): a year of moments cut from real clips, saved the
/// normal way. The captions and notes are sample content, like a person's own, so they aren't in the catalog.
extension AppDependencies {
    private struct DemoMoment {
        var back: String
        var front: String?
        var daysAgo: Int
        var hour: Int
        var minute = 0
        var caption = ""
        var note = ""
        var place: (String, Double, Double)?
    }

    private static let demoMoments: [DemoMoment] = [
        DemoMoment(back: "R10-dinner", daysAgo: 365, hour: 20, minute: 30, caption: "Dinner with friends", place: ("Yerevan", 40.18111, 44.51361)),
        DemoMoment(back: "R06-snow", front: "F04-snow", daysAgo: 282, hour: 17, minute: 50, caption: "First snow", place: ("Dilijan", 40.74056, 44.86306)),
        DemoMoment(back: "R08-blossom", daysAgo: 218, hour: 13, minute: 10, caption: "Blossom season", place: ("Yerevan", 40.18111, 44.51361)),
        DemoMoment(back: "R09-bike", daysAgo: 147, hour: 18, minute: 20, caption: "Evening ride"),
        DemoMoment(back: "R07-sea", front: "F05-beach", daysAgo: 119, hour: 20, caption: "Golden hour", place: ("Batumi", 41.61667, 41.63667)),
        DemoMoment(back: "R11-train", daysAgo: 99, hour: 19, minute: 30, caption: "Train home", place: ("Tbilisi", 41.71667, 44.78333)),
        DemoMoment(back: "R12-cake", daysAgo: 64, hour: 20, minute: 10, caption: "Thirty-two!"),
        DemoMoment(back: "R03-market", daysAgo: 43, hour: 10, minute: 20, caption: "Market haul", place: ("Yerevan", 40.18111, 44.51361)),
        DemoMoment(back: "R02-dog", front: "F02-park", daysAgo: 23, hour: 16, minute: 30, caption: "Leaves everywhere", place: ("Yerevan", 40.18111, 44.51361)),
        DemoMoment(back: "R05-baking", daysAgo: 9, hour: 11, minute: 15, caption: "Sunday bread"),
        DemoMoment(
            back: "R04-rain", front: "F03-cafe", daysAgo: 4, hour: 19, minute: 40, caption: "Rain and tea",
            note: "Finished the book at last. Rain all evening and nowhere to be.", place: ("Yerevan", 40.18111, 44.51361)
        ),
        DemoMoment(back: "R01-coffee", front: "F01-morning", daysAgo: 0, hour: 8, minute: 40, caption: "Slow morning", place: ("Yerevan", 40.18111, 44.51361)),
    ]

    /// The surprise a demo notification opens: with `-demo-surprise`, `xcrun simctl push` with this `promptID` in
    /// the payload opens the camera for it.
    static let demoPromptID = UUID(uuidString: "DE30DE30-0000-4000-8000-000000000001")!

    /// Six seconds of each clip; the selfie window where the camera puts it by default, on the 9:16 preview.
    func seedDemoMoments(from folder: URL) {
        let window = SelfieWindowFrame(frame: CGRect(x: 266.7, y: 140, width: 112, height: 150), preview: CGSize(width: 402, height: 715))
        let calendar = Calendar.current
        let now = Date()
        // Each recording starts with an empty lock screen, so a pushed surprise arrives on its own.
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        if ProcessInfo.processInfo.arguments.contains("-demo-surprise") {
            let prompt = SurprisePrompt(
                id: Self.demoPromptID, plannedAt: now, expiresAt: now.addingTimeInterval(15 * 60), notificationRequestID: "demo"
            )
            modelContainer.mainContext.insert(prompt)
            try? modelContainer.mainContext.save()
        }
        Task {
            for moment in Self.demoMoments {
                guard let back = DemoFootage.clip(moment.back, in: folder),
                      let day = calendar.date(byAdding: .day, value: -moment.daysAgo, to: now),
                      var date = calendar.date(bySettingHour: moment.hour, minute: moment.minute, second: 0, of: day),
                      let main = try? await DemoFootage.excerpt(of: back, from: 1, seconds: 6) else { continue }
                // Today's moment is never in the future.
                date = min(date, now.addingTimeInterval(-60))
                var selfie: URL?
                if let front = moment.front.flatMap({ DemoFootage.clip($0, in: folder) }) {
                    selfie = try? await DemoFootage.excerpt(of: front, from: 1, seconds: 6)
                }
                let video = CapturedVideo(mainURL: main, mainPosition: .back, selfieURL: selfie, duration: 6, selfieOffset: 0, hasAudio: false)
                let capture = CaptureResult(
                    media: .video(video), window: selfie == nil ? nil : .init(), capturedAt: CaptureTime(instant: date, timeZone: .current)
                )
                let place = moment.place.map { ReviewPlace.current(city: $0.0, at: GeoPoint(latitude: $0.1, longitude: $0.2, horizontalAccuracy: 30)) }
                _ = try? await momentSaver.save(MomentDraft(
                    capture: capture, caption: moment.caption, note: moment.note, window: selfie == nil ? nil : window, promptID: nil, place: place
                ))
            }
        }
    }
}
#endif
