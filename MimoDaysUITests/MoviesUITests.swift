import Core
import XCTest

/// Movies (F01-F15): flow 05, from the library to a finished movie.
final class MoviesUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot(), quality: .original)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Flow 05 (doc 02): new movie -> this year -> length -> moments -> build -> the editor -> export -> ready,
    /// then the finished movie is in the library.
    @MainActor
    func testAMovieIsMadeAndExported() {
        app = XCUIApplication()
        app.launchArguments = LaunchConfiguration(
            isUITesting: true, skipsOnboarding: true, seed: .movie, permissions: .granted
        ).arguments
        app.launch()
        app.tabBars.firstMatch.buttons.element(boundBy: 3).tap()

        let new = app.buttons["movies.new"]
        XCTAssertTrue(new.waitForExistence(timeout: 10))
        attachScreenshot("F01")
        // The seed's eight moments are saved in the background after launch, and F02 counts them when it
        // opens: reopen it until they are all there.
        let thisYear = app.buttons["newMovie.source.thisYear"]
        let deadline = Date().addingTimeInterval(30)
        while true {
            new.tap()
            XCTAssertTrue(thisYear.waitForExistence(timeout: 5))
            if thisYear.label.contains("8 moments") || Date() > deadline { break }
            app.buttons["newMovie.close"].tap()
            XCTAssertTrue(new.waitForExistence(timeout: 5))
        }
        XCTAssertTrue(thisYear.label.contains("8 moments"), thisYear.label)
        thisYear.tap()
        attachScreenshot("F02")
        app.buttons["newMovie.next"].firstMatch.tap()

        let full = app.buttons["newMovie.length.full"]
        XCTAssertTrue(full.waitForExistence(timeout: 5))
        full.tap()
        attachScreenshot("F04")
        app.buttons["newMovie.next"].firstMatch.tap()

        let build = app.buttons["newMovie.build"]
        XCTAssertTrue(build.waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(identifier: "newMovie.moment").count, 8)
        attachScreenshot("F05")
        build.tap()

        let export = app.buttons["editor.export"]
        XCTAssertTrue(export.waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons.matching(identifier: "editor.clip").count, 8)
        attachScreenshot("F06")
        export.tap()

        let start = app.buttons["export.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        attachScreenshot("F11")
        start.tap()

        let done = app.buttons["ready.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 180))
        attachScreenshot("F13")
        done.tap()

        let movie = app.buttons["movies.movie"]
        XCTAssertTrue(movie.waitForExistence(timeout: 5))
        attachScreenshot("F01 with the movie")
        movie.tap()
        XCTAssertTrue(app.buttons["movie.play"].waitForExistence(timeout: 5))
        attachScreenshot("F15")
    }
}
