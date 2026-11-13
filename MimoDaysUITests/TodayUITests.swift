import Core
import XCTest

/// Today (T01, T02, T06): what it shows and where each part leads.
final class TodayUITests: XCTestCase {
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
    }

    /// System tab bar buttons by position (Today, Memories, Map, Movies).
    @MainActor
    private func tab(_ index: Int) -> XCUIElement {
        app.tabBars.firstMatch.buttons.element(boundBy: index)
    }

    @MainActor
    func testBeforeTheFirstMomentTheHeroIsAnEmptyFrame() {
        launch(.empty)
        XCTAssertTrue(app.otherElements["today.emptyHero"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["capture"].label, "Catch your first moment")
        XCTAssertFalse(app.buttons["today.month"].exists)
        XCTAssertFalse(app.buttons["today.onThisDay"].exists)
        XCTAssertFalse(app.buttons["today.movie"].isEnabled)
    }

    @MainActor
    func testShowsTheLatestMomentThisMonthAndOnThisDay() {
        launch(.populated)
        let hero = app.descendants(matching: .any)["today.hero"]
        XCTAssertTrue(hero.waitForExistence(timeout: 10))
        XCTAssertTrue(hero.label.contains("Yerevan"), hero.label)
        XCTAssertEqual(app.buttons["capture"].label, "Catch a moment")
        XCTAssertTrue(app.buttons["today.month"].exists)
        XCTAssertTrue(app.buttons["today.onThisDay"].exists)
    }

    @MainActor
    func testThisMonthOpensMemories() {
        launch(.populated)
        let month = app.buttons["today.month"]
        XCTAssertTrue(month.waitForExistence(timeout: 10))
        month.tap()
        XCTAssertTrue(tab(1).isSelected)
    }

    @MainActor
    func testTheMovieCardOpensMovies() {
        launch(.populated)
        let movie = app.buttons["today.movie"]
        XCTAssertTrue(movie.waitForExistence(timeout: 10))
        app.swipeUp()
        movie.tap()
        XCTAssertTrue(tab(3).isSelected)
    }

    @MainActor
    func testCatchAMomentFromTodayShowsItThere() {
        launch(.empty)
        let capture = app.buttons["capture"]
        XCTAssertTrue(capture.waitForExistence(timeout: 5))
        capture.tap()
        let shutter = app.buttons["camera.shutter"]
        XCTAssertTrue(shutter.waitForExistence(timeout: 5))
        shutter.tap()
        let save = app.buttons["review.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 10))
        save.tap()
        XCTAssertTrue(app.descendants(matching: .any)["today.hero"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons["capture"].label, "Catch a moment")
    }

    @MainActor
    func testSettingsFromToday() {
        launch(.empty)
        let settings = app.buttons["settings"].firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
        let done = app.buttons["settings.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        done.tap()
        XCTAssertTrue(done.waitForNonExistence(timeout: 5))
        XCTAssertTrue(tab(0).isSelected)
    }
}
