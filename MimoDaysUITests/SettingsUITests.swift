import Core
import XCTest

/// Settings (S01-S08) as the sheet shows them.
final class SettingsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// S03 opened from Settings shows its rows; it was an empty page (Andrew, 2026-11-16).
    @MainActor
    func testCameraSettingsShowTheirRows() {
        let app = XCUIApplication()
        app.launchArguments = LaunchConfiguration(isUITesting: true, skipsOnboarding: true, seed: .populated, permissions: .granted).arguments
        app.launch()
        app.tabBars.firstMatch.buttons.element(boundBy: 1).tap()
        let settings = app.buttons["settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()
        app.buttons["settings.camera"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["cameraSettings.shutter"].waitForExistence(timeout: 5))
    }

    /// 14.9 (flow D01-D03): Settings > Donations lists the six tips with their prices; a tip thanks and goes back.
    @MainActor
    func testATipThanksAndGoesBack() {
        let app = XCUIApplication()
        app.launchArguments = LaunchConfiguration(isUITesting: true, skipsOnboarding: true, seed: .populated, permissions: .granted).arguments
        app.launch()
        app.tabBars.firstMatch.buttons.element(boundBy: 1).tap()
        let settings = app.buttons["settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()
        let donations = app.buttons["settings.donations"].firstMatch
        XCTAssertTrue(donations.waitForExistence(timeout: 5))
        donations.tap()
        for tier in ["small", "medium", "large", "generous", "patron", "extraordinary"] {
            XCTAssertTrue(app.buttons["donations.\(tier)"].waitForExistence(timeout: 5), tier)
        }
        let small = app.buttons["donations.small"]
        XCTAssertTrue(small.label.contains("$2.99"), small.label)
        // The tip's App Review screenshot (14.10).
        let shot = XCTAttachment(screenshot: app.screenshot(), quality: .original)
        shot.name = "D01"
        shot.lifetime = .keepAlways
        add(shot)
        small.tap()
        let done = app.buttons["donations.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Thank you!"].exists)
        done.tap()
        XCTAssertFalse(done.waitForExistence(timeout: 2))
        XCTAssertTrue(small.isHittable, "back on the tips, nothing else asked")
    }
}
