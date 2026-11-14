import Core
import XCTest

/// Map (P01-P03): flow 04, and flow 08 as far as Movies.
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

    /// Flow 08 (doc 02) up to Movies: a place's moments make a movie.
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
        XCTAssertTrue(app.tabBars.firstMatch.buttons.element(boundBy: 3).isSelected)
    }
}
