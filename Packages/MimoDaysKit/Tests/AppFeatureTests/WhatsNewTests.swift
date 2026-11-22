@testable import AppFeature
import Foundation
import Testing

/// §V17 LL03: What's new shows once after the 1.0.7 update.
@MainActor
struct WhatsNewTests {
    @Test func isDueUntilSeenAndStaysSeen() throws {
        let suite = "WhatsNew-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = WhatsNewPreferences.whatsNew(defaults, seen: false)
        #expect(first.value.isDue)
        first.markSeen()
        #expect(!WhatsNewPreferences.whatsNew(defaults, seen: false).value.isDue)
    }

    @Test func anEarlierReleaseSeenIsStillDue() {
        #expect(WhatsNewSettings(seenRelease: "1.0.6").isDue)
        #expect(!WhatsNewSettings(seenRelease: WhatsNewSettings.release).isDue)
    }

    @Test func uiTestsStartSeenUnlessAsked() {
        #expect(!WhatsNewPreferences.whatsNew(nil, seen: true).value.isDue)
        #expect(WhatsNewPreferences.whatsNew(nil, seen: false).value.isDue)
    }
}
