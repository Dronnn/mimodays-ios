import Core
import XCTest

/// C04: the selfie window moves by touch and hold (sheet) or by dragging it to a corner.
/// C06c: the microphone is explained the first time the camera is in Video.
final class CameraUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private var selfieWindow: XCUIElement {
        app.descendants(matching: .any)["camera.selfieWindow"]
    }

    @MainActor
    private func openCamera(permissions: PermissionStatus = .granted) {
        app = XCUIApplication()
        app.launchArguments = LaunchConfiguration(
            isUITesting: true, skipsOnboarding: true, seed: .empty, permissions: permissions
        ).arguments
        app.launch()
        app.buttons["capture"].tap()
        if permissions == .notDetermined {
            // C06 camera explainer first.
            app.buttons["permission.primary"].tap()
        }
        XCTAssertTrue(selfieWindow.waitForExistence(timeout: 5))
    }

    /// Flow 03 up to review: a photo to review and Retake back to the camera, then a video recorded, stopped
    /// and reviewed, on the simulated engine.
    @MainActor
    func testTakesAPhotoThenRecordsAndStopsAVideo() {
        openCamera()
        let shutter = app.buttons["camera.shutter"]
        shutter.tap()
        let retake = app.buttons["review.retake"]
        XCTAssertTrue(retake.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["review.selfieWindow"].exists)
        XCTAssertTrue(app.buttons["review.save"].exists)
        retake.tap()
        XCTAssertTrue(shutter.waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["camera.notice"].exists)

        app.buttons["camera.mode.video"].tap()
        app.buttons["camera.length.30"].tap()
        shutter.tap()
        let stop = app.buttons["camera.stop"]
        XCTAssertTrue(stop.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["camera.timer"].exists)
        // While recording the top controls give way to the timer.
        XCTAssertFalse(app.buttons["capture.close"].exists)
        stop.tap()
        // Review: the clip plays on tap; Save leaves the capture flow.
        let media = app.descendants(matching: .any)["review.media"]
        XCTAssertTrue(media.waitForExistence(timeout: 10))
        media.tap()
        app.buttons["review.save"].tap()
        XCTAssertTrue(app.buttons["capture"].waitForExistence(timeout: 5))
    }

    /// C07: the selfie window still moves in review, and Retake leaves the camera's own corner as it was.
    @MainActor
    func testTheSelfieWindowMovesInReviewOnly() {
        openCamera()
        app.buttons["camera.shutter"].tap()
        let window = app.descendants(matching: .any)["review.selfieWindow"]
        XCTAssertTrue(window.waitForExistence(timeout: 5))
        XCTAssertEqual(window.value as? String, "Top right, Medium")
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5)))
        XCTAssertEqual(window.value as? String, "Bottom left, Medium")
        app.buttons["review.retake"].tap()
        XCTAssertEqual(selfieWindow.value as? String, "Top right, Medium")
    }

    @MainActor
    func testFlipAndHideTheSelfieWindow() {
        openCamera()
        app.buttons["camera.flip"].tap()
        XCTAssertTrue(selfieWindow.exists)
        let toggle = app.buttons["camera.selfie"]
        XCTAssertEqual(toggle.value as? String, "On")
        toggle.tap()
        XCTAssertFalse(selfieWindow.waitForExistence(timeout: 1))
        XCTAssertEqual(toggle.value as? String, "Off")
        toggle.tap()
        XCTAssertTrue(selfieWindow.waitForExistence(timeout: 5))
    }

    @MainActor
    func testFirstVideoExplainsTheMicrophoneThenRecordsSound() {
        openCamera(permissions: .notDetermined)
        app.buttons["camera.mode.video"].tap()
        let allow = app.buttons["permission.primary"]
        XCTAssertTrue(allow.waitForExistence(timeout: 5))
        allow.tap()
        XCTAssertTrue(allow.waitForNonExistence(timeout: 5))
        let sound = app.buttons["camera.sound"]
        XCTAssertTrue(sound.waitForExistence(timeout: 5))
        XCTAssertEqual(sound.value as? String, "On")
    }

    @MainActor
    func testRecordWithoutSoundKeepsVideosSilentAndDoesNotAskAgain() {
        openCamera(permissions: .notDetermined)
        app.buttons["camera.mode.video"].tap()
        let withoutSound = app.buttons["permission.secondary"]
        XCTAssertTrue(withoutSound.waitForExistence(timeout: 5))
        withoutSound.tap()
        XCTAssertTrue(withoutSound.waitForNonExistence(timeout: 5))
        XCTAssertEqual(app.buttons["camera.sound"].value as? String, "Off")
        app.buttons["camera.mode.photo"].tap()
        app.buttons["camera.mode.video"].tap()
        XCTAssertFalse(app.buttons["permission.primary"].waitForExistence(timeout: 2))
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
