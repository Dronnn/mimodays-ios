import Core
import XCTest

final class MimoDaysUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Past onboarding, empty store, every permission in `permissions`.
    @MainActor
    private func launch(permissions: PermissionStatus = .granted) {
        app = XCUIApplication()
        app.launchArguments = LaunchConfiguration(
            isUITesting: true, skipsOnboarding: true, seed: .empty, permissions: permissions
        ).arguments
        app.launch()
    }

    /// System tab bar buttons by position (Today, Memories, Map, Movies); identifiers don't reach them.
    @MainActor
    private func tab(_ index: Int) -> XCUIElement {
        app.tabBars.firstMatch.buttons.element(boundBy: index)
    }

    @MainActor
    func testLaunchesOnToday() {
        launch()
        XCTAssertTrue(app.buttons["capture"].waitForExistence(timeout: 5))
        XCTAssertTrue(tab(0).isSelected)
    }

    @MainActor
    func testSwitchesTabs() {
        launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(app.tabBars.firstMatch.buttons.count, 4)
        for index in [1, 2, 3, 0] {
            tab(index).tap()
            XCTAssertTrue(tab(index).isSelected, "tab \(index) not selected")
        }
    }

    @MainActor
    func testOpensAndClosesSettings() {
        launch()
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
        launch()
        app.buttons["capture"].tap()
        let close = app.buttons["capture.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        close.tap()
        XCTAssertTrue(close.waitForNonExistence(timeout: 5))
    }

    @MainActor
    func testCameraExplainerLeadsToCamera() {
        launch(permissions: .notDetermined)
        app.buttons["capture"].tap()
        let continueButton = app.buttons["permission.primary"]
        XCTAssertTrue(continueButton.waitForExistence(timeout: 5))
        continueButton.tap()
        XCTAssertTrue(app.buttons["capture.close"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testCameraExplainerNotNowCloses() {
        launch(permissions: .notDetermined)
        app.buttons["capture"].tap()
        let notNow = app.buttons["permission.secondary"]
        XCTAssertTrue(notNow.waitForExistence(timeout: 5))
        notNow.tap()
        XCTAssertTrue(notNow.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["capture"].exists)
    }

    @MainActor
    func testCameraOffOffersSettings() {
        launch(permissions: .denied)
        app.buttons["capture"].tap()
        XCTAssertTrue(app.buttons["permission.primary"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["capture.close"].exists)
        app.buttons["permission.secondary"].tap()
        XCTAssertTrue(app.buttons["capture"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testLaunchPerformance() {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
