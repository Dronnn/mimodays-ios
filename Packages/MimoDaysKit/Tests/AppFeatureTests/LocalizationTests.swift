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
    ]

    private static var resourceKeys: [String] {
        let resources = MainTab.allCases.map(\.title)
            + PermissionScreen.allCases.flatMap { [$0.title, $0.message, $0.primaryAction, $0.secondaryAction] }
            + OnboardingPage.allCases.flatMap { [$0.title, $0.message, $0.primaryAction] }
            + SurpriseFrequency.allCases.map(\.label)
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
            #expect(entry.localizations?["en"]?.stringUnit.state == "translated", "no English: \(key)")
        }
    }

    private struct Catalog: Decodable {
        struct Entry: Decodable {
            struct Localization: Decodable {
                struct Unit: Decodable { var state: String }
                var stringUnit: Unit
            }

            var comment: String?
            var localizations: [String: Localization]?
        }

        var sourceLanguage: String
        var strings: [String: Entry]
    }
}
