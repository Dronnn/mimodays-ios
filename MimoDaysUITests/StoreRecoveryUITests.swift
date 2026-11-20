import Core
import XCTest

/// A library that can't be opened: the app shows a way back instead of crashing (Andrew, 2026-11-20).
final class StoreRecoveryUITests: XCTestCase {
    @MainActor
    func testABrokenStoreShowsRecoveryInsteadOfCrashing() {
        let app = XCUIApplication()
        app.launchArguments = LaunchConfiguration(isUITesting: true, skipsOnboarding: true, breaksStore: true).arguments
        app.launch()
        let tryAgain = app.buttons["recovery.tryAgain"]
        XCTAssertTrue(tryAgain.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["recovery.restore"].exists)
        tryAgain.tap()
        XCTAssertTrue(app.staticTexts["recovery.stillFails"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.state, .runningForeground)
    }
}
