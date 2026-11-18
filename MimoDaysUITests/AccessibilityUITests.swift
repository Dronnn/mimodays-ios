import Core
import XCTest

/// 15.2/15.3: VoiceOver's audit (labels, traits, 44 pt targets, Dynamic Type, clipped text) over the screens the
/// other suites don't audit: Today, the Memories timeline, the camera and Review, every Settings page, Movies and
/// Search. Contrast is checked
/// against the design instead.
final class AccessibilityUITests: XCTestCase {
    private var app: XCUIApplication!
    /// Every issue on every screen, reported together at the end.
    private var issues: [String] = []

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDown() {
        XCTAssertTrue(issues.isEmpty, issues.joined(separator: "\n"))
        issues = []
        super.tearDown()
    }

    @MainActor
    private func launch(_ seed: LaunchConfiguration.Seed) {
        app = XCUIApplication()
        app.launchArguments = LaunchConfiguration(isUITesting: true, skipsOnboarding: true, seed: seed, permissions: .granted).arguments
        app.launch()
    }

    @MainActor
    private func audit(_ screen: String) throws {
        let shot = XCTAttachment(screenshot: app.screenshot(), quality: .original)
        shot.name = screen
        shot.lifetime = .deleteOnSuccess
        add(shot)
        try app.performAccessibilityAudit(for: XCUIAccessibilityAuditType.all.subtracting(.contrast)) { issue in
            if self.isKnownFalsePositive(issue) { return true }
            let element = issue.element.map { "\($0.elementType) '\($0.identifier)' '\($0.label)' \($0.frame)" } ?? "-"
            self.issues.append("\(screen): \(issue.compactDescription) - \(element)")
            return true
        }
    }

    /// What the audit reports that isn't so, each checked on screenshots at the default size and at AX3
    /// (2026-11-16): letter-spaced capitals (`labelCaps`) and text fields reported as clipped though shown whole; the
    /// keyboard's own suggestion bar; the system toolbar's Done, which iOS caps; the lens segment "Ultra wide",
    /// shown whole on one line.
    @MainActor
    private func isKnownFalsePositive(_ issue: XCUIAccessibilityAuditIssue) -> Bool {
        guard let element = issue.element else { return false }
        switch issue.auditType {
        case .textClipped:
            let label = element.label
            let isSpacedCaps = label == label.uppercased() && label.contains { $0.isLetter }
            return isSpacedCaps || element.elementType == .textField || label == "Ultra wide"
        case .sufficientElementDescription:
            let keyboard = app.keyboards.firstMatch
            return element.label.isEmpty && keyboard.exists && element.frame.minY >= keyboard.frame.minY - 50
        case .dynamicType:
            return element.identifier == "cameraSettings.done"
        default:
            return false
        }
    }

    @MainActor
    func testTheCameraAndReviewPassTheAudit() throws {
        launch(.empty)
        app.buttons["capture"].tap()
        XCTAssertTrue(app.buttons["camera.shutter"].waitForExistence(timeout: 10))
        try audit("camera")
        app.buttons["camera.more"].tap()
        XCTAssertTrue(app.buttons["cameraSettings.done"].waitForExistence(timeout: 5))
        try audit("camera ••• sheet")
        app.buttons["cameraSettings.done"].tap()
        app.buttons["camera.shutter"].tap()
        XCTAssertTrue(app.buttons["review.save"].waitForExistence(timeout: 10))
        try audit("review")
    }

    @MainActor
    func testEverySettingsPagePassesTheAudit() throws {
        launch(.populated)
        app.tabBars.firstMatch.buttons.element(boundBy: 1).tap()
        let settings = app.buttons["settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()
        XCTAssertTrue(app.buttons["settings.done"].waitForExistence(timeout: 5))
        try audit("settings")
        // Import opens the system photo picker: Apple's screen, not audited.
        for page in ["surprises", "camera", "memories", "movies", "privacy", "appearance", "backup", "storage", "donations", "help"] {
            let row = app.buttons["settings.\(page)"].firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 5), page)
            for _ in 0 ..< 4 where !row.isHittable { app.scrollViews.firstMatch.swipeUp(velocity: .slow) }
            row.tap()
            // The page's back, not the Memories header's settings button under the sheet.
            let back = app.buttons.matching(NSPredicate(format: "label == 'Settings' AND identifier != 'settings'")).firstMatch
            XCTAssertTrue(back.waitForExistence(timeout: 5), page)
            sleep(1)
            try audit("settings > \(page)")
            back.tap()
        }
    }

    @MainActor
    func testTodayAndTheMemoriesTimelinePassTheAudit() throws {
        launch(.populated)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "today.hero").firstMatch.waitForExistence(timeout: 20))
        try audit("today")
        app.tabBars.firstMatch.buttons.element(boundBy: 1).tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "memories.tile").firstMatch.waitForExistence(timeout: 20))
        try audit("memories")
    }

    @MainActor
    func testMoviesAndTheWizardPassTheAudit() throws {
        launch(.movie)
        app.tabBars.firstMatch.buttons.element(boundBy: 3).tap()
        let new = app.buttons["movies.new"]
        XCTAssertTrue(new.waitForExistence(timeout: 10))
        try audit("movies")
        new.tap()
        XCTAssertTrue(app.buttons["newMovie.source.thisYear"].waitForExistence(timeout: 5))
        try audit("new movie")
    }

    @MainActor
    func testSearchPassesTheAudit() throws {
        launch(.populated)
        app.tabBars.firstMatch.buttons.element(boundBy: 1).tap()
        let search = app.buttons["memories.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 20))
        search.tap()
        let field = app.textFields["search.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        try audit("search")
        field.typeText("yere")
        XCTAssertTrue(app.buttons["search.place"].waitForExistence(timeout: 10))
        try audit("search results")
    }
}
