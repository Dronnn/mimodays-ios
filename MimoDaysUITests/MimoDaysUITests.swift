import Core
import XCTest

final class MimoDaysUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = LaunchConfiguration(isUITesting: true, skipsOnboarding: true, seed: .empty).arguments
    }

    /// System tab bar buttons by position (Today, Memories, Map, Movies); identifiers don't reach them.
    private func tab(_ index: Int) -> XCUIElement {
        app.tabBars.firstMatch.buttons.element(boundBy: index)
    }

    @MainActor
    func testLaunchesOnToday() {
        app.launch()
        XCTAssertTrue(app.buttons["capture"].waitForExistence(timeout: 5))
        XCTAssertTrue(tab(0).isSelected)
    }

    @MainActor
    func testSwitchesTabs() {
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(app.tabBars.firstMatch.buttons.count, 4)
        for index in [1, 2, 3, 0] {
            tab(index).tap()
            XCTAssertTrue(tab(index).isSelected, "tab \(index) not selected")
        }
    }

    @MainActor
    func testOpensAndClosesSettings() {
        app.launch()
        tab(2).tap()
        app.buttons["settings"].firstMatch.tap()
        let done = app.buttons["settings.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        done.tap()
        XCTAssertTrue(done.waitForNonExistence(timeout: 5))
        XCTAssertTrue(tab(2).isSelected)
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
