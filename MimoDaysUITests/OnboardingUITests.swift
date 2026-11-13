import Core
import XCTest

/// Flow 01: first launch, onboarding, reminders, first capture. Each launch starts with an empty store.
final class OnboardingUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launch(permissions: PermissionStatus = .notDetermined) {
        app = XCUIApplication()
        app.launchArguments = LaunchConfiguration(isUITesting: true, seed: .empty, permissions: permissions).arguments
        app.launch()
    }

    /// The pages sit side by side, so only the visible page's button can be tapped.
    @MainActor
    private func visibleButton(_ identifier: String) -> XCUIElement {
        app.buttons.matching(identifier: identifier).allElementsBoundByIndex.first { $0.isHittable }
            ?? app.buttons[identifier]
    }

    @MainActor
    private func tap(_ identifier: String, file: StaticString = #filePath, line: UInt = #line) {
        let button = app.buttons[identifier].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 5), "missing \(identifier)", file: file, line: line)
        visibleButton(identifier).tap()
    }

    @MainActor
    func testSkipEnableRemindersThenLaterLandsOnToday() {
        launch()
        tap("onboarding.skip")
        tap("reminders.enable")
        XCTAssertTrue(app.buttons["reminders.continue"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["reminders.openSettings"].exists)
        tap("reminders.continue")
        tap("firstCapture.later")
        XCTAssertTrue(app.buttons["capture"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.firstMatch.buttons.element(boundBy: 0).isSelected)
    }

    @MainActor
    func testContinueThroughEveryPageAndBack() {
        launch()
        for _ in 0..<6 { tap("onboarding.continue") }
        XCTAssertTrue(app.buttons["reminders.enable"].waitForExistence(timeout: 5))
        tap("back")
        XCTAssertTrue(app.buttons["onboarding.continue"].waitForExistence(timeout: 5))
        XCTAssertFalse(visibleButton("onboarding.skip").isHittable, "the last page has no Skip")
    }

    @MainActor
    func testMaybeLaterHasNoSettingsButton() {
        launch()
        tap("onboarding.skip")
        tap("reminders.later")
        XCTAssertTrue(app.buttons["reminders.continue"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["reminders.openSettings"].exists)
    }

    @MainActor
    func testDeniedRemindersOfferSettings() {
        launch(permissions: .denied)
        tap("onboarding.skip")
        tap("reminders.enable")
        XCTAssertTrue(app.buttons["reminders.openSettings"].waitForExistence(timeout: 5))
        tap("reminders.continue")
        XCTAssertTrue(app.buttons["firstCapture.capture"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testFirstCaptureOpensTheCameraExplainerAndCloses() {
        launch()
        tap("onboarding.skip")
        tap("reminders.later")
        tap("reminders.continue")
        tap("firstCapture.capture")
        tap("permission.primary")
        tap("capture.close")
        XCTAssertTrue(app.buttons["firstCapture.capture"].waitForExistence(timeout: 5))
    }

    /// Everything except contrast: coral links (3.71) and the cream label on the coral button (2.78) are below
    /// WCAG in light mode by design, approved by Andrew on 2026-11-13 (design tokens doc, "kept as designed").
    @MainActor
    private func audit() throws {
        try app.performAccessibilityAudit(for: XCUIAccessibilityAuditType.all.subtracting(.contrast))
    }

    /// Accessibility audit on every onboarding screen.
    @MainActor
    func testOnboardingScreensPassAccessibilityAudit() throws {
        launch()
        try audit()
        tap("onboarding.skip")
        XCTAssertTrue(app.buttons["reminders.enable"].waitForExistence(timeout: 5))
        try audit()
        tap("reminders.enable")
        XCTAssertTrue(app.buttons["reminders.continue"].waitForExistence(timeout: 5))
        try audit()
        tap("reminders.continue")
        XCTAssertTrue(app.buttons["firstCapture.capture"].waitForExistence(timeout: 5))
        try audit()
    }
}
