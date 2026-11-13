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

    @Test func settingsRouteClosesCamera() {
        let router = AppRouter(selectedTab: .movies)
        router.open(.capture(promptID: nil))
        router.open(.settings)
        #expect(router.isSettingsPresented)
        #expect(router.capture == nil)
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
        router.open(.capture(promptID: nil))
        #expect(router.capture?.id != first)
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
}
