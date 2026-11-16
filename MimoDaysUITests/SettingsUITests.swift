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
}
