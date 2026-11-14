import Core
import XCTest

/// Map (P01-P03): flow 04, and flow 08 into the movie wizard.
final class MapUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launchOnMap() {
        app = XCUIApplication()
        app.launchArguments = LaunchConfiguration(
            isUITesting: true, skipsOnboarding: true, seed: .populated, permissions: .granted
        ).arguments
        app.launch()
        app.tabBars.firstMatch.buttons.element(boundBy: 2).tap()
    }

    @MainActor
    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot(), quality: .original)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Flow 04 (doc 02): the map, a place (P02), its moments (P03), one of them in the viewer.
    @MainActor
    func testAPlaceOpensItsMomentsAndTheViewer() {
        launchOnMap()
        // The seed saves the Yerevan moment last.
        let recent = app.buttons["map.recentPlace"]
        XCTAssertTrue(recent.waitForExistence(timeout: 20))
        attachScreenshot("P01")
        recent.tap()
        let seeAll = app.buttons["place.seeAll"]
        XCTAssertTrue(seeAll.waitForExistence(timeout: 5))
        attachScreenshot("P02")
        seeAll.tap()
        let tile = app.buttons["place.tile"]
        XCTAssertTrue(tile.waitForExistence(timeout: 5))
        attachScreenshot("P03")
        tile.tap()
        XCTAssertTrue(app.buttons["viewer.favorite"].waitForExistence(timeout: 10))
    }

    /// Flow 08 (doc 02): a place's moments make a movie. The wizard opens on Movies with the place chosen;
    /// the seed's Yerevan has one moment, so Next explains that a movie needs five (F16).
    @MainActor
    func testAPlaceMakesAMovie() {
        launchOnMap()
        let recent = app.buttons["map.recentPlace"]
        XCTAssertTrue(recent.waitForExistence(timeout: 20))
        recent.tap()
        app.buttons["place.seeAll"].tap()
        let movie = app.buttons["place.movie"]
        XCTAssertTrue(movie.waitForExistence(timeout: 5))
        movie.tap()
        let next = app.buttons["newMovie.next"]
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["newMovie.source.place"].label.contains("Yerevan"), app.buttons["newMovie.source.place"].label)
        attachScreenshot("F02 from a place")
        next.tap()
        XCTAssertTrue(app.buttons["newMovie.moreDates"].waitForExistence(timeout: 5))
        attachScreenshot("F16")
    }

    /// 10.6: every place as a list, the way through the map without seeing it - a place, then one of its moments.
    @MainActor
    func testAllPlacesListsEveryPlaceAndOpensOne() {
        launchOnMap()
        let all = app.buttons["map.allPlaces"]
        XCTAssertTrue(all.waitForExistence(timeout: 20))
        all.tap()
        let place = app.buttons["map.place"]
        XCTAssertTrue(place.waitForExistence(timeout: 5))
        XCTAssertTrue(place.label.contains("Yerevan"), place.label)
        place.tap()
        let tile = app.buttons["place.tile"]
        XCTAssertTrue(tile.waitForExistence(timeout: 5))
        tile.tap()
        XCTAssertTrue(app.buttons["viewer.favorite"].waitForExistence(timeout: 10))
    }

    /// VoiceOver's audit without contrast (checked against the design) and without MapKit's own Legal label, whose
    /// small hit area is Apple's.
    @MainActor
    private func audit(_ types: XCUIAccessibilityAuditType = XCUIAccessibilityAuditType.all.subtracting(.contrast)) throws {
        try app.performAccessibilityAudit(for: types) { issue in
            issue.auditType == .hitRegion && issue.detailedDescription.contains("MKAttributionLabel")
        }
    }

    /// The map, a place's sheet and its page pass VoiceOver's audit (contrast is checked against the design).
    @MainActor
    func testMapScreensPassAccessibilityAudit() throws {
        launchOnMap()
        let recent = app.buttons["map.recentPlace"]
        XCTAssertTrue(recent.waitForExistence(timeout: 20))
        try audit()
        recent.tap()
        let seeAll = app.buttons["place.seeAll"]
        XCTAssertTrue(seeAll.waitForExistence(timeout: 5))
        // P02 without the clipped-text check: it reports the sheet's texts as clipped although at the largest text
        // size the sheet grows with them and shows them whole (run at AccessibilityXXXL, 2026-11-14).
        try audit(XCUIAccessibilityAuditType.all.subtracting([.contrast, .textClipped]))
        seeAll.tap()
        XCTAssertTrue(app.buttons["place.tile"].waitForExistence(timeout: 5))
        try audit()
    }
}
