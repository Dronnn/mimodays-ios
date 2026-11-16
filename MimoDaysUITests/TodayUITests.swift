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
        // The seed saves its moments one by one; the newest, in Yerevan, lands last.
        let hero = app.descendants(matching: .any)["today.hero"]
        let newest = expectation(for: NSPredicate(format: "label CONTAINS 'Yerevan'"), evaluatedWith: hero)
        wait(for: [newest], timeout: 20)
        XCTAssertEqual(app.buttons["capture"].label, "Catch a moment")
        XCTAssertTrue(app.buttons["today.month"].exists)
        XCTAssertTrue(app.buttons["today.onThisDay"].exists)
    }

    /// A tile of this month opens its card: the strip on iPhone, the grid on iPad (Andrew, 2026-11-16: the iPad's
    /// tiles opened nothing).
    @MainActor
    func testAMonthTileOpensItsCard() {
        launch(.populated)
        let grid = app.buttons["today.monthTile"].firstMatch
        let strip = app.descendants(matching: .any)["today.strip"].buttons.firstMatch
        XCTAssertTrue(grid.waitForExistence(timeout: 10) || strip.waitForExistence(timeout: 5))
        (grid.exists ? grid : strip).tap()
        XCTAssertTrue(app.buttons["viewer.favorite"].waitForExistence(timeout: 10))
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
        // The seed saves its moments one by one; the card waits for the first.
        let enabled = expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: movie)
        wait(for: [enabled], timeout: 20)
        // On the first screen as in T02; smaller phones scroll to it.
        if !movie.isHittable { app.swipeUp() }
        // On this day sits under the card; its cropped photo must not take the tap.
        movie.tap()
        XCTAssertTrue(tab(3).isSelected)
    }

    /// T01: with nothing saved the movie card waits, dimmed, at the bottom - where T02 has it - 12 pt over the tab bar.
    @MainActor
    func testWithNothingYetTheMovieCardWaitsAtTheBottom() {
        launch(.empty)
        let movie = app.buttons["today.movie"]
        XCTAssertTrue(movie.waitForExistence(timeout: 5))
        XCTAssertFalse(movie.isEnabled)
        XCTAssertEqual(app.tabBars.firstMatch.frame.minY - movie.frame.maxY, 12, accuracy: 2)
        let attachment = XCTAttachment(screenshot: app.screenshot(), quality: .original)
        attachment.name = "today-empty"
        attachment.lifetime = .keepAlways
        add(attachment)
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

    /// U10-U15: Mosaic in the header shows the Mosaic; a piece opens its Memory Card, back returns to the Mosaic;
    /// Today in the header shows Today again. The Mosaic passes the accessibility audit.
    @MainActor
    func testTheHomeSwitchesToTheMosaicAndBack() throws {
        launch(.populated)
        let mosaicSwitch = app.buttons["home.mosaic"]
        XCTAssertTrue(mosaicSwitch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["home.today"].isSelected)
        mosaicSwitch.tap()
        let piece = app.buttons.matching(identifier: "mosaic.piece").firstMatch
        XCTAssertTrue(piece.waitForExistence(timeout: 10))
        XCTAssertTrue(mosaicSwitch.isSelected)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "U13"
        shot.lifetime = .keepAlways
        add(shot)
        try app.performAccessibilityAudit(for: XCUIAccessibilityAuditType.all.subtracting(.contrast))

        piece.tap()
        let back = app.buttons["viewer.back"]
        XCTAssertTrue(back.waitForExistence(timeout: 10))
        XCTAssertTrue(back.staticTexts["Mosaic"].exists || back.label.contains("Back"))
        // The Mosaic's card swaps and turns over as everywhere else.
        app.swapAndFlipTheCard()
        back.tap()
        XCTAssertTrue(piece.waitForExistence(timeout: 5))

        app.buttons["home.today"].tap()
        XCTAssertTrue(app.buttons["home.today"].isSelected)
        XCTAssertTrue(app.buttons["capture"].waitForExistence(timeout: 5))
    }
}
