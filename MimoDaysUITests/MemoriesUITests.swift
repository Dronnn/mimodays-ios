import Core
import XCTest

/// Memories (M01, M01e).
final class MemoriesUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launch(_ seed: LaunchConfiguration.Seed) {
        app = XCUIApplication()
        app.launchArguments = LaunchConfiguration(
            isUITesting: true, skipsOnboarding: true, seed: seed, permissions: .granted
        ).arguments
        app.launch()
        app.tabBars.firstMatch.buttons.element(boundBy: 1).tap()
    }

    @MainActor
    func testSavedMomentsAreInTheTimeline() {
        launch(.populated)
        // A year ago may still be below the fold, where the lazy list hasn't made it yet.
        let tiles = app.descendants(matching: .any).matching(identifier: "memories.tile")
        let all = expectation(for: NSPredicate(format: "count >= 3"), evaluatedWith: tiles)
        wait(for: [all], timeout: 20)
    }

    @MainActor
    func testBeforeTheFirstMomentItLeadsToTheCamera() {
        launch(.empty)
        let capture = app.buttons["memories.capture"]
        XCTAssertTrue(capture.waitForExistence(timeout: 5))
        capture.tap()
        XCTAssertTrue(app.buttons["capture.close"].waitForExistence(timeout: 5))
    }
}
