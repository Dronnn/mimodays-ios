import Core
import XCTest

/// Backup and restore (E03-E08): flow 06, through the system's own file pickers.
final class BackupUITests: XCTestCase {
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

    /// Flow 06 (doc 02): Settings -> Backup -> back up -> save in Files -> restore that file, replacing everything.
    @MainActor
    func testABackupIsSavedAndRestored() throws {
        app = XCUIApplication()
        app.launchArguments = LaunchConfiguration(
            isUITesting: true, skipsOnboarding: true, seed: .movie, permissions: .granted
        ).arguments
        app.launch()
        app.tabBars.firstMatch.buttons.element(boundBy: 1).tap()

        let settings = app.buttons["settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()
        app.buttons["settings.backup"].firstMatch.tap()

        let now = app.buttons["backup.now"]
        XCTAssertTrue(now.waitForExistence(timeout: 5))
        attachScreenshot("E06")
        now.tap()
        let create = app.buttons["backup.create"]
        XCTAssertTrue(create.waitForExistence(timeout: 5))
        attachScreenshot("E03")
        create.tap()

        // Files' own picker opens once the backup is packed and checked.
        let move = app.buttons["DOCPicker.actionButton"]
        XCTAssertTrue(move.waitForExistence(timeout: 60))
        attachScreenshot("E04p picker")
        // On hosted CI runners every query stalls for half a minute or more (and then times out) while Files'
        // picker goes away; packing and checking are covered up to here, the rest runs locally.
        try XCTSkipIf(ProcessInfo.processInfo.environment["MIMODAYS_CI"] == "1", "Files' picker stalls on CI runners")
        move.tap()
        // A backup from an earlier run on the same day has the same name.
        let replaceExisting = app.buttons["Replace"]
        if replaceExisting.waitForExistence(timeout: 3) { replaceExisting.tap() }
        let done = app.buttons["backup.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 30))
        attachScreenshot("E04")
        done.tap()

        let restore = app.buttons["backup.restore"]
        XCTAssertTrue(restore.waitForExistence(timeout: 5))
        restore.tap()
        let file = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'MimoDays-'")).firstMatch
        if !file.waitForExistence(timeout: 10) {
            app.buttons["Browse"].firstMatch.tap()
            let onMyPhone = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'On My iPhone'")).firstMatch
            if onMyPhone.waitForExistence(timeout: 5) { onMyPhone.tap() }
        }
        XCTAssertTrue(file.waitForExistence(timeout: 10))
        attachScreenshot("Files")
        file.tap()

        let replace = app.buttons["restore.replace"]
        XCTAssertTrue(replace.waitForExistence(timeout: 60))
        attachScreenshot("E07")
        replace.tap()
        app.buttons["restore.start"].tap()
        let restored = app.buttons["restore.done"]
        XCTAssertTrue(restored.waitForExistence(timeout: 60))
        attachScreenshot("E08")
    }
}
