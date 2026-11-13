@testable import AppFeature
@testable import Core
import Foundation
import Testing

@MainActor
struct CameraModelMicrophoneTests {
    private func videoCamera(engine: SimulatedCaptureEngine, allowed: Bool) async -> CameraModel {
        var settings = CameraSettings()
        settings.opensIn = .video
        let model = CameraModel(
            engine: engine, store: InMemoryCameraSettingsStore(settings), isSurprise: false,
            microphoneAllowed: { allowed }, onCapture: { _ in }
        )
        await model.start()
        return model
    }

    private func eventually(_ condition: () async -> Bool) async -> Bool {
        for _ in 0..<50 {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return false
    }

    @Test func videoWithPermissionAndSoundUsesTheMicrophone() async {
        let engine = SimulatedCaptureEngine()
        let model = await videoCamera(engine: engine, allowed: true)
        #expect(model.microphoneOn)
        #expect(await engine.hasMicrophone)
    }

    @Test func noPermissionNoMicrophone() async {
        let engine = SimulatedCaptureEngine()
        let model = await videoCamera(engine: engine, allowed: false)
        #expect(!model.microphoneOn)
        #expect(!(await engine.hasMicrophone))
    }

    /// "Record sound" off in the ••• sheet (or "Record without sound" in C06c) turns the microphone off.
    @Test func turningSoundOffInSettingsStopsTheMicrophone() async {
        let engine = SimulatedCaptureEngine()
        let model = await videoCamera(engine: engine, allowed: true)
        model.settings.recordsSound = false
        #expect(await eventually { await !engine.hasMicrophone })
    }

    @Test func photoModeNeverUsesTheMicrophone() async {
        let engine = SimulatedCaptureEngine()
        let model = await videoCamera(engine: engine, allowed: true)
        model.mode = .photo
        #expect(await eventually { await !engine.hasMicrophone })
    }
}
