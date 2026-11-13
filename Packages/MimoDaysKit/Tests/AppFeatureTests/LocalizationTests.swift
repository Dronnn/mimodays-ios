@testable import AppFeature
import Foundation
import Persistence
import Testing

struct LocalizationTests {
    private static let missing = "\u{0}missing"

    /// Keys used directly as `Text("…", bundle: .module)`.
    private static let literalKeys = ["Settings", "Capture", "Done", "Close", "A little surprise", "Skip", "Page %lld of %lld",
        "Back", "When should MimoDays surprise you?", "Pick how often and when. The exact time is always a surprise.",
        "How often", "On these days", "Earliest", "Latest", "Surprises only arrive between these times. Focus modes still apply.",
        "Enable reminders", "Maybe later", "Your first surprise is on its way.", "No reminders for now. That's okay.",
        "You can still capture moments whenever you like. To get surprises later, turn on notifications for MimoDays in Settings.",
        "Open iOS Settings", "Ready for your first little moment?", "Try the camera. Save the photo or video only if you like it.",
        "Capture my first moment", "I'll do it later", "Your first moment is here.",
        "It lives on this iPhone. Come back tomorrow, or whenever a surprise arrives.", "View my moments", "Today, %@",
        "Camera settings", "Flash", "Sound", "Selfie window", "On", "Off", "Switch camera", "Take photo", "Record video",
        "Stop recording", "Recording", "Tap to stop",
        "This iPhone can use one camera at a time. Tap ↻ to switch between you and the world.",
        "Opens in", "Video length", "Record sound", "Camera sounds", "Camera", "Photo", "Video",
        "Top left", "Top right", "Bottom left", "Bottom right", "Small", "Medium", "Large", "Reset to default",
        "Adjust selfie window",
        "Videos will be silent. Turn on the microphone in Settings to add sound.",
        "Not enough space to record. Free up some space on this iPhone and try again.",
        "The camera is busy with a call or another app. It comes back on its own.",
        "This iPhone is too warm for the camera right now. It comes back once it cools down.",
        "The camera paused for a moment. It comes back on its own.",
        "The camera isn't available right now. Close and try again in a moment.",
        "That one didn't come out. Try again.",
        "Retake", "Add a few words (optional)", "Caption", "Save", "Record again", "Save %lld seconds",
        "Plays the video", "Pauses the video", "Saved to today", "Manage storage", "Try again", "Not now",
        "Not enough space to save", "This moment is kept until you free up about %@. Nothing is lost.",
        "This moment didn't save", "Nothing is lost. Try again in a moment.",
        "A call stopped the recording at %@. The part before the call is kept.",
        "The recording stopped at %@ when you left MimoDays. The part before is kept.",
        "This iPhone got too warm, so the recording stopped at %@. The part before is kept.",
        "This iPhone ran out of space, so the recording stopped at %@. The part before is kept.",
        "The recording stopped at %@. The part before is kept.",
    ]

    private static var resourceKeys: [String] {
        let resources = MainTab.allCases.map(\.title)
            + PermissionScreen.allCases.flatMap { [$0.title, $0.message, $0.primaryAction, $0.secondaryAction] }
            + OnboardingPage.allCases.flatMap { [$0.title, $0.message, $0.primaryAction] }
            + SurpriseFrequency.allCases.map(\.label)
            + CameraSettings.VideoLength.allCases.map(\.settingsLabel)
            + SurpriseFrequency.allCases.map { frequency in
                var schedule = ReminderSchedule()
                schedule.frequency = frequency
                return schedule.summary(calendar: .current, locale: .current)
            }
            + (OnboardingPage.allCases.flatMap(\.artLayers) + FirstCaptureView.artLayers).compactMap { layer -> LocalizedStringResource? in
                guard case let .text(.localized(resource), _, _, _, _) = layer else { return nil }
                return resource
            }
        return resources.map(\.key)
    }

    @Test(arguments: resourceKeys + literalKeys)
    func everyUsedKeyIsInTheCatalog(key: String) {
        #expect(Bundle.module.localizedString(forKey: key, value: Self.missing, table: nil) != Self.missing)
    }

    /// Translators need a comment for every string, and English must be complete.
    @Test func everyCatalogEntryHasCommentAndEnglish() throws {
        let url = URL(filePath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Sources/AppFeature/Resources/Localizable.xcstrings")
        let catalog = try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: url))
        #expect(catalog.sourceLanguage == "en")
        for (key, entry) in catalog.strings {
            #expect(entry.comment?.isEmpty == false, "no comment: \(key)")
            let english = entry.localizations?["en"]
            let units = english?.stringUnit.map { [$0] } ?? english?.variations?.plural?.values.map(\.stringUnit) ?? []
            #expect(!units.isEmpty && units.allSatisfy { $0.state == "translated" }, "no English: \(key)")
        }
    }

    private struct Catalog: Decodable {
        struct Entry: Decodable {
            struct Localization: Decodable {
                struct Unit: Decodable { var state: String }
                struct Variant: Decodable { var stringUnit: Unit }
                struct Variations: Decodable { var plural: [String: Variant]? }
                var stringUnit: Unit?
                var variations: Variations?
            }

            var comment: String?
            var localizations: [String: Localization]?
        }

        var sourceLanguage: String
        var strings: [String: Entry]
    }
}
