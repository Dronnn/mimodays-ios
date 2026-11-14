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

    /// M02 → M04 and back: the calendar opens on today, which the seed has a moment on.
    @MainActor
    func testTheCalendarOpensADay() {
        launch(.populated)
        let calendar = app.buttons["Calendar"]
        XCTAssertTrue(calendar.waitForExistence(timeout: 10))
        calendar.tap()
        let openDay = app.buttons["calendar.openDay"]
        XCTAssertTrue(openDay.waitForExistence(timeout: 10))
        openDay.tap()
        XCTAssertTrue(app.descendants(matching: .any)["day.moment"].firstMatch.waitForExistence(timeout: 10))
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(openDay.waitForExistence(timeout: 5))
    }

    /// M01 → M05: a tile opens the viewer, the heart is kept, a swipe goes to the next moment.
    @MainActor
    func testATileOpensTheViewer() {
        launch(.populated)
        let tile = app.descendants(matching: .any).matching(identifier: "memories.tile").firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 20))
        tile.tap()
        let favorite = app.buttons["viewer.favorite"]
        XCTAssertTrue(favorite.waitForExistence(timeout: 10))
        let wasFavorite = favorite.isSelected
        favorite.tap()
        let flipped = expectation(for: NSPredicate(format: "isSelected == %@", NSNumber(value: !wasFavorite)), evaluatedWith: favorite)
        wait(for: [flipped], timeout: 5)
        app.swipeLeft()
        XCTAssertTrue(favorite.waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(tile.waitForExistence(timeout: 5))
    }

    /// M05 → M07 → M05: a caption added in Edit moment shows in the viewer.
    @MainActor
    func testEditingAddsACaption() {
        launch(.populated)
        let tile = app.descendants(matching: .any).matching(identifier: "memories.tile").firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 20))
        tile.tap()
        let edit = app.buttons["viewer.edit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 10))
        edit.tap()
        let caption = app.textFields["edit.caption"]
        XCTAssertTrue(caption.waitForExistence(timeout: 5))
        caption.tap()
        caption.typeText("Snow day")
        app.buttons["edit.save"].tap()
        XCTAssertTrue(app.staticTexts["Snow day"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["edit.save"].exists)
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
