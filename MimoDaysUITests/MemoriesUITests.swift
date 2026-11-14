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

    /// M08: the newest seeded moment is in Yerevan; the place, its moment, the viewer, back, filters, Cancel.
    @MainActor
    func testSearchFindsAPlaceAndOpensItsMoment() {
        launch(.populated)
        let search = app.buttons["memories.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 20))
        search.tap()
        let field = app.textFields["search.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("yere")
        let place = app.buttons["search.place"]
        XCTAssertTrue(place.waitForExistence(timeout: 10))
        place.tap()
        XCTAssertTrue(app.buttons["search.chip.place"].waitForExistence(timeout: 5))
        let result = app.descendants(matching: .any).matching(identifier: "search.result").firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        result.tap()
        XCTAssertTrue(app.buttons["viewer.favorite"].waitForExistence(timeout: 10))
        app.navigationBars.buttons.firstMatch.tap()
        let filters = app.buttons["search.filters"]
        XCTAssertTrue(filters.waitForExistence(timeout: 5))
        filters.tap()
        let show = app.buttons["filters.show"]
        XCTAssertTrue(show.waitForExistence(timeout: 5))
        show.tap()
        app.buttons["search.cancel"].tap()
        XCTAssertTrue(search.waitForExistence(timeout: 5))
    }

    /// M05 → M10: a moment given a heart is in Favorites; M10e before that.
    @MainActor
    func testAHeartedMomentIsInFavorites() {
        launch(.populated)
        let chip = app.buttons["memories.favorites"]
        XCTAssertTrue(chip.waitForExistence(timeout: 20))
        chip.tap()
        XCTAssertTrue(app.staticTexts["No favorites yet"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        let tile = app.descendants(matching: .any).matching(identifier: "memories.tile").firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 10))
        tile.tap()
        let favorite = app.buttons["viewer.favorite"]
        XCTAssertTrue(favorite.waitForExistence(timeout: 10))
        favorite.tap()
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(chip.waitForExistence(timeout: 5))
        chip.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "memories.tile").firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["No favorites yet"].exists)
    }

    /// M11 → M11b → M12: a new collection, a moment added to it.
    @MainActor
    func testANewCollectionGetsAMoment() {
        launch(.populated)
        let chip = app.buttons["memories.collections"]
        XCTAssertTrue(chip.waitForExistence(timeout: 20))
        chip.tap()
        let create = app.buttons["collections.create"]
        XCTAssertTrue(create.waitForExistence(timeout: 5))
        create.tap()
        let name = app.textFields["collection.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.typeText("Weekend trips")
        app.buttons["collection.create"].tap()
        let card = app.descendants(matching: .any).matching(identifier: "collections.card").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.tap()
        let add = app.buttons["collection.add"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()
        let pick = app.descendants(matching: .any).matching(identifier: "memories.tile").firstMatch
        XCTAssertTrue(pick.waitForExistence(timeout: 5))
        pick.tap()
        app.buttons["addMoments.add"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "memories.tile").firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Weekend trips"].exists)
    }

    /// M05 → M15 → M11 → M16 → M16b: a deleted moment waits in Recently deleted and comes back with Recover.
    @MainActor
    func testADeletedMomentCanBeRecovered() {
        launch(.populated)
        let tile = app.descendants(matching: .any).matching(identifier: "memories.tile").firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 20))
        tile.tap()
        let delete = app.buttons["viewer.delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: 10))
        delete.tap()
        let confirm = app.buttons["delete.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        let chip = app.buttons["memories.collections"]
        XCTAssertTrue(chip.waitForExistence(timeout: 10))
        chip.tap()
        let row = app.buttons["collections.recentlyDeleted"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        let deleted = app.buttons["deleted.tile"].firstMatch
        XCTAssertTrue(deleted.waitForExistence(timeout: 5))
        deleted.tap()
        let recover = app.buttons["deleted.recover"]
        XCTAssertTrue(recover.waitForExistence(timeout: 5))
        recover.tap()
        XCTAssertTrue(app.staticTexts["Recently deleted"].waitForExistence(timeout: 5))
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: deleted)
        wait(for: [gone], timeout: 5)
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
