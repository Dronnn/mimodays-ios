import Core
import XCTest

/// C04: the selfie window moves by touch and hold (sheet) or by dragging it to a corner.
final class CameraUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private var selfieWindow: XCUIElement {
        app.descendants(matching: .any)["camera.selfieWindow"]
    }

    @MainActor
    private func openCamera() {
        app = XCUIApplication()
        app.launchArguments = LaunchConfiguration(
            isUITesting: true, skipsOnboarding: true, seed: .empty, permissions: .granted
        ).arguments
        app.launch()
        app.buttons["capture"].tap()
        XCTAssertTrue(selfieWindow.waitForExistence(timeout: 5))
    }

    @MainActor
    func testTouchAndHoldOpensTheSheetAndResetRestoresTheDefault() {
        openCamera()
        XCTAssertEqual(selfieWindow.value as? String, "Top right, Medium")
        selfieWindow.press(forDuration: 1)
        let bottomLeft = app.buttons["Bottom left"]
        XCTAssertTrue(bottomLeft.waitForExistence(timeout: 5))
        bottomLeft.tap()
        app.buttons["Large"].tap()
        XCTAssertEqual(selfieWindow.value as? String, "Bottom left, Large")
        app.buttons["selfieWindow.reset"].tap()
        XCTAssertEqual(selfieWindow.value as? String, "Top right, Medium")
    }

    @MainActor
    func testDraggingSnapsToTheNearestCornerAndIsKept() {
        openCamera()
        let start = selfieWindow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.6)))
        XCTAssertEqual(selfieWindow.value as? String, "Bottom left, Medium")
        // Reopening the camera keeps the corner.
        app.buttons["capture.close"].tap()
        app.buttons["capture"].tap()
        XCTAssertTrue(selfieWindow.waitForExistence(timeout: 5))
        XCTAssertEqual(selfieWindow.value as? String, "Bottom left, Medium")
    }
}
