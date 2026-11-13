@testable import AppFeature
import Core
import Testing

struct CameraAccessStepTests {
    @Test(arguments: [
        (PermissionStatus.notDetermined, CameraAccessStep.explain),
        (.granted, .camera),
        (.limited, .camera),
        (.denied, .openSettings),
        (.restricted, .openSettings),
    ])
    func stepForEveryStatus(_ status: PermissionStatus, _ expected: CameraAccessStep) {
        #expect(CameraAccessStep(status) == expected)
    }

    @Test func onlyTheTurnedOffScreensKeepActionsUnderTheText() {
        #expect(PermissionScreen.allCases.filter { !$0.pinsActions } == [.cameraOff, .microphoneOff])
    }
}
