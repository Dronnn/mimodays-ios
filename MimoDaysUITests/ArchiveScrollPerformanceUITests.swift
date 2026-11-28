import Core
import XCTest

/// P5.4: Memories' timeline and the Mosaic scrolled through a year of moments (about 1,100), hitches and frame rate
/// measured. Local runs only: a hosted runner's simulator times the runner, not the app.
final class ArchiveScrollPerformanceUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["MIMODAYS_CI"] == "1", "Scrolling is timed on a local simulator only")
        continueAfterFailure = false
    }

    /// Launches with the year seeded and waits for all of it: this month's count, as the seed makes it (3 a day so far).
    @MainActor
    private func launchWithAYear() {
        app = XCUIApplication()
        app.launchArguments = LaunchConfiguration(isUITesting: true, skipsOnboarding: true, seed: .year, permissions: .granted).arguments
        app.launch()
        app.tabBars.firstMatch.buttons.element(boundBy: 1).tap()
        let now = Date()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let thisMonth = (0..<365).flatMap { back in
            [9, 13, 19].compactMap { hour in
                calendar.date(byAdding: .day, value: -back, to: today).flatMap { calendar.date(bySettingHour: hour, minute: 0, second: 0, of: $0) }
            }
        }.filter { $0 < now && calendar.isDate($0, equalTo: now, toGranularity: .month) }.count
        let count = app.staticTexts["\(thisMonth) moments"]
        XCTAssertTrue(count.waitForExistence(timeout: 600))
    }

    @MainActor
    func testTheTimelineScrollsThroughAYear() {
        launchWithAYear()
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        measure(metrics: [XCTOSSignpostMetric.scrollDecelerationMetric, XCTOSSignpostMetric.scrollDraggingMetric], options: options) {
            for _ in 0..<6 { app.swipeUp(velocity: .fast) }
            for _ in 0..<6 { app.swipeDown(velocity: .fast) }
        }
    }

    @MainActor
    func testTheMosaicScrollsThroughAYear() {
        launchWithAYear()
        app.tabBars.firstMatch.buttons.element(boundBy: 0).tap()
        let mosaic = app.buttons["home.mosaic"]
        XCTAssertTrue(mosaic.waitForExistence(timeout: 10))
        mosaic.tap()
        XCTAssertTrue(app.buttons.matching(identifier: "mosaic.piece").firstMatch.waitForExistence(timeout: 20))
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        measure(metrics: [XCTOSSignpostMetric.scrollDecelerationMetric, XCTOSSignpostMetric.scrollDraggingMetric], options: options) {
            for _ in 0..<6 { app.swipeUp(velocity: .fast) }
            for _ in 0..<6 { app.swipeDown(velocity: .fast) }
        }
    }
}
