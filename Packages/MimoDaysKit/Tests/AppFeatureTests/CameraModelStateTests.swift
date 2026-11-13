@testable import AppFeature
@testable import Core
import Foundation
import Testing

/// 6.10: the camera's state machine on the simulated engine.
@MainActor
struct CameraModelStateTests {
    private final class Captures {
        var results: [CaptureResult] = []
        deinit { results.forEach { $0.discardFiles() } }
    }

    private func camera(
        _ engine: any CaptureEngine = SimulatedCaptureEngine(), mode: CameraSettings.Mode = .photo, captures: Captures = Captures()
    ) async -> CameraModel {
        var settings = CameraSettings()
        settings.opensIn = mode
        let model = CameraModel(
            engine: engine, store: InMemoryCameraSettingsStore(settings), isSurprise: false,
            microphoneStatus: { .granted }, onCapture: { captures.results.append($0) }
        )
        #expect(model.phase == .starting)
        await model.start()
        return model
    }

    private func eventually(_ condition: () -> Bool) async throws {
        for _ in 0..<50 where !condition() { try await Task.sleep(for: .milliseconds(20)) }
    }

    @Test func dualStartsReadyWithTheRearCameraBig() async {
        let model = await camera()
        #expect(model.phase == .ready)
        #expect(model.setup == .dual)
        #expect(model.mainPosition == .back && model.selfiePosition == .front)
        #expect(!model.showsSingleCameraNote)
        #expect(model.canCapture)
    }

    @Test func singleStartsOnTheRearWithTheNote() async {
        let model = await camera(SimulatedCaptureEngine(multiCam: false))
        #expect(model.setup == .single(.back))
        #expect(model.selfiePosition == nil)
        #expect(model.showsSingleCameraNote)
        #expect(!model.canToggleSelfie)
    }

    @Test func noCameraFails() async {
        let model = await camera(AVCaptureEngine())
        #expect(model.phase == .failed(.cameraUnavailable))
        #expect(!model.canCapture)
    }

    @Test func flipSwapsOnDualAndSwitchesOnSingle() async {
        let dual = await camera()
        await dual.flip()
        #expect(dual.isSwapped && dual.mainPosition == .front && dual.selfiePosition == .back)

        let single = await camera(SimulatedCaptureEngine(multiCam: false))
        await single.flip()
        #expect(single.setup == .single(.front))
        #expect(!single.showsSingleCameraNote)
    }

    @Test func aSwappedPhotoKeepsTheFrontCameraAsMain() async throws {
        let captures = Captures()
        let model = await camera(captures: captures)
        await model.flip()
        await model.shutter()
        guard case let .photo(photo, _, _) = try #require(captures.results.first) else { Issue.record("not a photo"); return }
        #expect(photo.mainPosition == .front)
        #expect(photo.selfieURL != nil)
        #expect(model.phase == .ready)
    }

    @Test func aHiddenSelfieWindowIsNeverKept() async throws {
        let captures = Captures()
        let model = await camera(captures: captures)
        model.toggleSelfie()
        #expect(model.selfiePosition == nil)
        await model.shutter()
        guard case let .photo(photo, window, composedURL) = try #require(captures.results.first) else { Issue.record("not a photo"); return }
        #expect(photo.selfieURL == nil && window == nil && composedURL == nil)
    }

    @Test func recordingStopsOnTheSecondTapAndLocksTheControls() async throws {
        let captures = Captures()
        let model = await camera(mode: .video, captures: captures)
        async let first: Void = model.shutter()
        try await eventually { model.isRecording }
        #expect(model.isRecording && !model.canCapture)
        model.toggleSelfie()
        await model.flip()
        #expect(model.selfiePosition == .front && !model.isSwapped)
        await model.shutter()
        await first
        #expect(model.phase == .ready)
        guard case let .video(video, _) = try #require(captures.results.first) else { Issue.record("not a video"); return }
        #expect(video.selfieURL != nil && video.interruption == nil)
    }

    @Test func recordingTimerShowsElapsedAgainstTheLimit() async {
        let model = await camera(mode: .video)
        let start = Date(timeIntervalSince1970: 1_000)
        model.phase = .recording(startedAt: start)
        #expect(model.recordingLabel(at: start.addingTimeInterval(7.5)) == "00:07 / 00:10")
        #expect(abs(model.recordingProgress(at: start.addingTimeInterval(7.5)) - 0.75) < 0.001)
        #expect(model.recordingProgress(at: start.addingTimeInterval(20)) == 1)
        model.settings.videoLength = .long
        #expect(model.recordingLabel(at: start.addingTimeInterval(61)) == "01:00 / 01:00")
    }

    @Test func droppingTheSelfieCameraUnderPressureEndsTheSwap() async throws {
        let engine = SimulatedCaptureEngine()
        let model = await camera(engine)
        await model.flip()
        await engine.simulatePressure(.critical)
        try await eventually { model.setup == .single(.back) }
        #expect(model.setup == .single(.back))
        #expect(!model.isSwapped && model.mainPosition == .back)
    }
}
