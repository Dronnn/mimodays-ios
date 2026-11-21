@testable import AppFeature
import Foundation
import Testing

@MainActor
struct AppRouterTests {
    @Test func startsOnTodayWithNothingPresented() {
        let router = AppRouter()
        #expect(router.selectedTab == .today)
        #expect(!router.isSettingsPresented)
        #expect(router.capture == nil)
    }

    @Test func tabRouteSelectsTabAndDismissesEverything() {
        let router = AppRouter()
        router.open(.settings)
        router.open(.tab(.map))
        #expect(router.selectedTab == .map)
        #expect(!router.isSettingsPresented)
        #expect(router.capture == nil)
    }

    /// The camera or Review isn't cut short by a link: it opens once they close, the latest one.
    @Test func aLinkWaitsForTheCameraToClose() {
        let router = AppRouter(selectedTab: .movies)
        router.open(.capture(promptID: nil))
        let shown = router.capture
        router.open(.tab(.map))
        router.open(.settings)
        router.open(.capture(promptID: UUID()))
        #expect(router.capture == shown && !router.isSettingsPresented && router.selectedTab == .today)
        router.capture = nil
        // Only once the cover is gone: one still closing would take the next with it.
        #expect(!router.isSettingsPresented)
        router.captureDismissed()
        #expect(router.isSettingsPresented && router.held == nil)
    }

    /// P8.11: the words being written aren't cut short either, a surprise included; it opens once they're saved
    /// or discarded.
    @Test func everythingWaitsForWriting() {
        let router = AppRouter(selectedTab: .memories)
        router.open(.write)
        #expect(router.writing != nil && router.selectedTab == .today)
        let prompt = UUID()
        router.open(.capture(promptID: prompt))
        router.open(.write)
        #expect(router.capture == nil)
        router.writing = nil
        router.captureDismissed()
        #expect(router.capture?.promptID == prompt && router.writing == nil && router.held == nil)
    }

    @Test func surpriseOpensCameraOnTodayOverSettings() {
        let router = AppRouter(selectedTab: .memories)
        router.open(.settings)
        let prompt = UUID()
        router.open(.capture(promptID: prompt))
        #expect(router.selectedTab == .today)
        #expect(!router.isSettingsPresented)
        #expect(router.capture?.promptID == prompt)
        #expect(router.capture?.isSurprise == true)
    }

    @Test func plainCaptureIsNotASurprise() {
        let router = AppRouter()
        router.open(.capture(promptID: nil))
        #expect(router.capture?.isSurprise == false)
    }

    @Test func eachCaptureRequestIsANewPresentation() {
        let router = AppRouter()
        router.open(.capture(promptID: nil))
        let first = router.capture?.id
        // Over an open camera nothing starts again; once it's closed, the next one is new.
        router.open(.capture(promptID: nil))
        #expect(router.capture?.id == first)
        router.capture = nil
        router.open(.capture(promptID: nil))
        #expect(router.capture != nil && router.capture?.id != first)
    }

    @Test(arguments: [
        ("mimodays://today", Route.tab(.today)),
        ("mimodays://memories", Route.tab(.memories)),
        ("mimodays://map", Route.tab(.map)),
        ("mimodays://movies", Route.tab(.movies)),
        ("mimodays://settings", Route.settings),
        ("mimodays://capture", Route.capture(promptID: nil)),
        ("mimodays://capture?prompt=6F1C2B3A-0000-4000-8000-000000000001",
         Route.capture(promptID: UUID(uuidString: "6F1C2B3A-0000-4000-8000-000000000001"))),
        ("mimodays://capture?prompt=not-a-uuid", Route.capture(promptID: nil)),
    ])
    func parsesURLs(string: String, expected: Route) throws {
        let url = try #require(URL(string: string))
        #expect(AppRouter.route(from: url) == expected)
    }

    @Test(arguments: ["https://today", "mimodays://unknown", "mimodays:"])
    func rejectsForeignURLs(string: String) throws {
        let url = try #require(URL(string: string))
        #expect(AppRouter.route(from: url) == nil)
    }

    @Test func notificationWithPromptOpensCamera() {
        let id = UUID()
        #expect(AppRouter.route(fromNotification: [AppRouter.promptIDKey: id.uuidString]) == .capture(promptID: id))
    }

    @Test func notificationWithoutValidPromptIsIgnored() {
        #expect(AppRouter.route(fromNotification: [:]) == nil)
        #expect(AppRouter.route(fromNotification: [AppRouter.promptIDKey: "nope"]) == nil)
        #expect(AppRouter.route(fromNotification: [AppRouter.promptIDKey: 42]) == nil)
    }

    @Test func tabTitlesComeFromTheCatalog() {
        let titles = MainTab.allCases.map { String(localized: $0.title) }
        #expect(titles == ["Today", "Memories", "Map", "Movies"])
    }

    /// P2.0: a surprise tapped while the camera is up opens when it closes, if it can still be answered.
    @Test(arguments: [true, false])
    func aSurpriseDuringACaptureWaitsForIt(answerable: Bool) {
        let router = AppRouter()
        router.isAnswerable = { _ in answerable }
        router.open(.capture(promptID: nil))
        let id = UUID()
        router.heldSurprise = id
        router.open(.settings)
        router.capture = nil
        #expect(router.capture == nil)
        router.captureDismissed()
        #expect(router.capture?.promptID == (answerable ? id : nil))
        #expect(router.isSettingsPresented == !answerable)
    }

    /// P8.8: "Capture this again" opens a plain camera that knows what it repeats; not over an open one.
    @Test func captureAgainOpensAPlainCameraForIt() {
        let router = AppRouter(selectedTab: .memories)
        let source = UUID()
        router.open(.captureAgain(source))
        #expect(router.selectedTab == .today)
        #expect(router.capture?.repeatOf == source && router.capture?.promptID == nil && router.capture?.isSurprise == false)
        let shown = router.capture?.id
        router.open(.captureAgain(UUID()))
        #expect(router.capture?.id == shown)
    }
}
