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
        // Our explainer before the system prompt, here too (Andrew, 2026-11-19).
        XCTAssertTrue(app.descendants(matching: .any)["permission.notifications"].waitForExistence(timeout: 5))
        tap("permission.primary")
        XCTAssertTrue(app.buttons["reminders.continue"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["reminders.openSettings"].exists)
        tap("reminders.continue")
        tap("firstCapture.later")
        XCTAssertTrue(app.buttons["capture"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.firstMatch.buttons.element(boundBy: 0).isSelected)
    }

    /// §V17 LL03: over Today once for someone who updated; Continue closes it.
    @MainActor
    func testWhatsNewOpensOverTodayAndContinueClosesIt() {
        app = XCUIApplication()
        app.launchArguments = LaunchConfiguration(
            isUITesting: true, skipsOnboarding: true, seed: .empty, permissions: .granted, showsWhatsNew: true
        ).arguments
        app.launch()
        XCTAssertTrue(app.buttons["whatsNew.continue"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["capture"].isHittable)
        tap("whatsNew.continue")
        XCTAssertTrue(app.buttons["capture"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["whatsNew.continue"].exists)
    }

    @MainActor
    /// Onboarding shows the new pages, so What's new doesn't follow it, even when it would be due.
    func testANewInstallSeesNoWhatsNew() {
        app = XCUIApplication()
        app.launchArguments = LaunchConfiguration(isUITesting: true, seed: .empty, showsWhatsNew: true).arguments
        app.launch()
        tap("onboarding.skip")
        tap("reminders.later")
        tap("reminders.continue")
        tap("firstCapture.later")
        XCTAssertTrue(app.buttons["capture"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["whatsNew.continue"].exists)
    }

    @MainActor
    func testContinueThroughEveryPageAndBack() {
        launch()
        for _ in 0..<8 { tap("onboarding.continue") }
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

    /// P2.4, W03: notifications off, so the first surprise shows at the top of onboarding a few seconds after the
    /// reminders step; Open brings its camera (here the camera-off explainer), and closing it returns to the page.
    @MainActor
    func testWithoutNotificationsTheFirstSurpriseShowsInTheApp() {
        launch(permissions: .denied)
        tap("onboarding.skip")
        tap("reminders.enable")
        XCTAssertTrue(app.buttons["reminders.openSettings"].waitForExistence(timeout: 5))
        let ribbon = app.descendants(matching: .any)["onboarding.surprise"]
        XCTAssertTrue(ribbon.waitForExistence(timeout: 20))
        // Open sits at the ribbon's trailing end.
        ribbon.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        XCTAssertTrue(app.descendants(matching: .any)["permission.cameraOff"].waitForExistence(timeout: 5))
        tap("permission.secondary")
        XCTAssertTrue(app.buttons["reminders.openSettings"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testFirstCaptureOpensTheCameraExplainerAndCloses() {
        launch()
        tap("onboarding.skip")
        tap("reminders.later")
        tap("reminders.continue")
        tap("firstCapture.capture")
        tap("permission.primary")
        // The camera opens in Video, so the microphone is explained next.
        XCTAssertTrue(app.descendants(matching: .any)["permission.microphone"].waitForExistence(timeout: 5))
        tap("permission.primary")
        tap("capture.close")
        XCTAssertTrue(app.buttons["firstCapture.capture"].waitForExistence(timeout: 5))
    }

    /// Everything except contrast: coral links (3.71) and the cream label on the coral button (2.78) are below
    /// WCAG in light mode by design, approved by Andrew on 2026-11-13 (design tokens doc, "kept as designed").
    @MainActor
    private func audit() throws {
        // A busy CI machine can run out of the audit's own time ("Audit failed to complete in time"); that is the
        // machine, not the screen, so it gets one more go, as in AccessibilityUITests.
        for attempt in 1...2 {
            do {
                try app.performAccessibilityAudit(for: XCUIAccessibilityAuditType.all.subtracting(.contrast))
                return
            } catch where attempt == 1 && "\(error)".localizedCaseInsensitiveContains("in time") {
                continue
            }
        }
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
        XCTAssertTrue(app.descendants(matching: .any)["permission.notifications"].waitForExistence(timeout: 5))
        try audit()
        tap("permission.primary")
        XCTAssertTrue(app.buttons["reminders.continue"].waitForExistence(timeout: 5))
        try audit()
        tap("reminders.continue")
        XCTAssertTrue(app.buttons["firstCapture.capture"].waitForExistence(timeout: 5))
        try audit()
    }
}
