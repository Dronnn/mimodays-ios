import Core
import XCTest

/// Flow 02: a surprise notification tap opens the camera (simulated at launch with `-surprise-tap`).
final class SurpriseUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launch(tap: LaunchConfiguration.SurpriseTap) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = LaunchConfiguration(
            isUITesting: true, skipsOnboarding: true, seed: .empty, permissions: .granted, surpriseTap: tap
        ).arguments
        app.launch()
        return app
    }

    @MainActor
    func testTapInTimeOpensTheSurpriseCamera() {
        let app = launch(tap: .inTime)
        XCTAssertTrue(app.otherElements["camera"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["camera.surprise"].exists)
        // Not now: closing is safe and lands on Today.
        app.buttons["capture.close"].tap()
        XCTAssertTrue(app.buttons["capture"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.firstMatch.buttons.element(boundBy: 0).isSelected)
    }

    @MainActor
    func testTapAfterExpiryOpensAPlainCamera() {
        let app = launch(tap: .expired)
        XCTAssertTrue(app.otherElements["camera"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["camera.surprise"].exists)
    }
}
