import AVFoundation
import Core
import CoreLocation
import Photos
import Testing
import UserNotifications

struct PermissionTests {
    @Test(arguments: [
        (AVAuthorizationStatus.notDetermined, PermissionStatus.notDetermined),
        (.authorized, .granted), (.denied, .denied), (.restricted, .restricted),
    ])
    func cameraAndMicrophone(_ system: AVAuthorizationStatus, _ expected: PermissionStatus) {
        #expect(PermissionStatus(system) == expected)
    }

    @Test(arguments: [
        (PHAuthorizationStatus.notDetermined, PermissionStatus.notDetermined),
        (.authorized, .granted), (.limited, .limited), (.denied, .denied), (.restricted, .restricted),
    ])
    func photoLibrary(_ system: PHAuthorizationStatus, _ expected: PermissionStatus) {
        #expect(PermissionStatus(system) == expected)
    }

    @Test(arguments: [
        (CLAuthorizationStatus.notDetermined, CLAccuracyAuthorization.fullAccuracy, PermissionStatus.notDetermined),
        (.authorizedWhenInUse, .fullAccuracy, .granted),
        (.authorizedAlways, .fullAccuracy, .granted),
        (.authorizedWhenInUse, .reducedAccuracy, .limited),
        (.denied, .fullAccuracy, .denied),
        (.restricted, .fullAccuracy, .restricted),
    ])
    func location(_ system: CLAuthorizationStatus, _ accuracy: CLAccuracyAuthorization, _ expected: PermissionStatus) {
        #expect(PermissionStatus(system, accuracy: accuracy) == expected)
    }

    @Test(arguments: [
        (UNAuthorizationStatus.notDetermined, PermissionStatus.notDetermined),
        (.authorized, .granted), (.provisional, .limited), (.ephemeral, .limited), (.denied, .denied),
    ])
    func notifications(_ system: UNAuthorizationStatus, _ expected: PermissionStatus) {
        #expect(PermissionStatus(system) == expected)
    }

    @Test func usableAndSettingsStates() {
        #expect([PermissionStatus.granted, .limited].allSatisfy { $0.isUsable })
        #expect(![PermissionStatus.notDetermined, .denied, .restricted].contains { $0.isUsable })
        #expect([PermissionStatus.denied, .restricted].allSatisfy { $0.needsSettings })
        #expect(![PermissionStatus.notDetermined, .granted, .limited].contains { $0.needsSettings })
    }

    @Test func presetAnswersOnlyUndeterminedRequests() async {
        let undetermined = PresetPermissionService(status: .notDetermined, requestResult: .denied)
        #expect(await undetermined.status(of: .camera) == .notDetermined)
        #expect(await undetermined.request(.camera) == .denied)
        #expect(await undetermined.status(of: .camera) == .denied)
        #expect(await undetermined.status(of: .microphone) == .notDetermined)

        let granted = PresetPermissionService(status: .granted, requestResult: .denied)
        #expect(await granted.request(.location) == .granted)
    }
}
