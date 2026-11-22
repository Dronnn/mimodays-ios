import Core
import XCTest

/// P8.12: Today › Add a moment › Add from Journaling Suggestions, with a stand-in for Apple's picker (the simulator
/// doesn't have it).
final class JournalingUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launch(_ fixture: LaunchConfiguration.JournalingFixture) {
        app = XCUIApplication()
        app.launchArguments = LaunchConfiguration(
            isUITesting: true, skipsOnboarding: true, seed: .empty, permissions: .granted, journaling: fixture
        ).arguments
        app.launch()
        let menu = app.buttons["today.addMoment"]
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        menu.tap()
        let item = app.buttons["addMoment.journaling"]
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        item.tap()
    }

    /// DD04: Continue waits for a photo; the chosen one goes to the import review with Import 1.
    @MainActor
    func testAPhotoGoesToTheImportReview() {
        launch(.photos)
        let continueButton = app.buttons["journaling.continue"]
        XCTAssertTrue(continueButton.waitForExistence(timeout: 5))
        XCTAssertFalse(continueButton.isEnabled)
        app.buttons.matching(identifier: "journaling.asset").element(boundBy: 1).tap()
        XCTAssertTrue(continueButton.isEnabled)
        continueButton.tap()
        XCTAssertTrue(app.buttons["import.start"].waitForExistence(timeout: 10))
    }

    /// DD05: a prompt opens Write a moment with it as the hint.
    @MainActor
    func testAPromptOpensWriteAMoment() {
        launch(.prompt)
        let continueButton = app.buttons["journaling.continue"]
        XCTAssertTrue(continueButton.waitForExistence(timeout: 5))
        continueButton.tap()
        XCTAssertTrue(app.descendants(matching: .any)["textMoment.prompt"].waitForExistence(timeout: 5))
    }

    /// Nothing to add: Choose another suggestion goes back to the picker.
    @MainActor
    func testNothingToAddOffersAnotherSuggestion() {
        launch(.nothing)
        let again = app.buttons["journaling.chooseAgain"]
        XCTAssertTrue(again.waitForExistence(timeout: 5))
        again.tap()
        // The stand-in picker hands back the same suggestion at once.
        XCTAssertTrue(app.buttons["journaling.chooseAgain"].waitForExistence(timeout: 5))
        app.buttons["journaling.cancel"].tap()
        XCTAssertTrue(app.buttons["today.addMoment"].waitForExistence(timeout: 5))
    }
}
