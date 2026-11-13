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
        XCTAssertTrue(app.descendants(matching: .any)["camera.surprise"].exists)
        // Not now: closing is safe and lands on Today.
        app.buttons["capture.close"].tap()
        XCTAssertTrue(app.buttons["capture"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.firstMatch.buttons.element(boundBy: 0).isSelected)
    }

    /// 7.7: from the notification a moment is kept in two taps, shutter and Save, with nothing in between.
    @MainActor
    func testASurpriseIsKeptInTwoTaps() {
        let app = launch(tap: .inTime)
        let shutter = app.buttons["camera.shutter"]
        XCTAssertTrue(shutter.waitForExistence(timeout: 5))
        shutter.tap()
        let save = app.buttons["review.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        // 7.6: review marks it as a surprise.
        XCTAssertTrue(app.descendants(matching: .any)["review.time"].label.hasPrefix("Surprise moment"))
        save.tap()
        XCTAssertTrue(app.descendants(matching: .any)["savedToast"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["capture"].exists)
    }

    @MainActor
    func testTapAfterExpiryOpensAPlainCamera() {
        let app = launch(tap: .expired)
        XCTAssertTrue(app.otherElements["camera"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["camera.surprise"].exists)
    }
}
