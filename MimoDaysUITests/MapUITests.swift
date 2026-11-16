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

    /// H.2: on iPhone the interface stays upright when the phone turns; the map and its places stay usable.
    @MainActor
    func testTheMapStaysUprightWhenThePhoneTurns() {
        launchOnMap()
        defer { XCUIDevice.shared.orientation = .portrait }
        let recent = app.buttons["map.recentPlace"]
        XCTAssertTrue(recent.waitForExistence(timeout: 20))
        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(1)
        let window = app.windows.firstMatch.frame
        XCTAssertGreaterThan(window.height, window.width, "the screen stays upright: \(window)")
        XCTAssertTrue(recent.isHittable)
        recent.tap()
        XCTAssertTrue(app.buttons["place.seeAll"].waitForExistence(timeout: 5))
    }

    /// H.10: the places panel's grabber drags it down to its title and up to half the screen (Andrew, 2026-11-16).
    @MainActor
    func testThePlacesPanelDragsBetweenItsHeights() {
        launchOnMap()
        let grabber = app.descendants(matching: .any)["map.panelGrabber"]
        XCTAssertTrue(grabber.waitForExistence(timeout: 20))
        XCTAssertEqual(grabber.value as? String, "Recent places")
        let window = app.windows.firstMatch
        func drag(to y: CGFloat) {
            grabber.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(
                forDuration: 0.2, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: y)),
                withVelocity: .slow, thenHoldForDuration: 0.2
            )
        }
        drag(to: 0.97)
        XCTAssertEqual(grabber.value as? String, "Collapsed")
        drag(to: 0.3)
        XCTAssertEqual(grabber.value as? String, "Half screen")
        XCTAssertTrue(app.buttons["map.recentPlace"].firstMatch.isHittable)
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
        // U41: back to the Map, which of the place's moments this is.
        attachScreenshot("U41")
        // The Map's card swaps and turns over as everywhere else.
        app.swapAndFlipTheCard()
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
