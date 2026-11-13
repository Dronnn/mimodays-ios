@testable import AppFeature
import Foundation
import Testing

struct LocalizationTests {
    private static let missing = "\u{0}missing"

    /// Keys used directly as `Text("…", bundle: .module)`.
    private static let literalKeys = ["Settings", "Capture", "Done", "Close", "A little surprise", "Skip", "Page %lld of %lld"]

    private static var resourceKeys: [String] {
        let resources = MainTab.allCases.map(\.title)
            + PermissionScreen.allCases.flatMap { [$0.title, $0.message, $0.primaryAction, $0.secondaryAction] }
            + OnboardingPage.allCases.flatMap { [$0.title, $0.message, $0.primaryAction] }
            + OnboardingPage.allCases.flatMap(\.artLayers).compactMap { layer -> LocalizedStringResource? in
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
