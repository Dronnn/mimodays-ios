import Core
import XCTest

final class MimoDaysUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = LaunchConfiguration(isUITesting: true, skipsOnboarding: true, seed: .empty).arguments
    }

    @MainActor
    func testLaunchesOnToday() {
        app.launch()
        XCTAssertTrue(app.buttons["capture"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["tab.today"].isSelected)
    }

    @MainActor
    func testSwitchesTabs() {
        app.launch()
        for tab in ["memories", "map", "movies", "today"] {
            let button = app.buttons["tab.\(tab)"]
            XCTAssertTrue(button.waitForExistence(timeout: 5))
            button.tap()
            XCTAssertTrue(button.isSelected, "tab \(tab) not selected")
        }
    }

    @MainActor
    func testOpensAndClosesSettings() {
        app.launch()
        app.buttons["tab.map"].tap()
        app.buttons["settings"].firstMatch.tap()
        let done = app.buttons["settings.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        done.tap()
        XCTAssertTrue(done.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["tab.map"].isSelected)
    }

    @MainActor
    func testOpensAndClosesCamera() {
        app.launch()
        app.buttons["capture"].tap()
        let close = app.buttons["capture.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        close.tap()
        XCTAssertTrue(close.waitForNonExistence(timeout: 5))
    }

    @MainActor
    func testLaunchPerformance() {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
