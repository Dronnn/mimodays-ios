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
            microphoneStatus: { allowed ? .granted : .denied }, onCapture: { _ in }
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

@MainActor
struct CameraModelInterruptionTests {
    @Test func aCallDuringRecordingHandsOverThePartBeforeIt() async throws {
        let engine = SimulatedCaptureEngine()
        var results: [CaptureResult] = []
        var settings = CameraSettings()
        settings.opensIn = .video
        settings.videoLength = .long
        let model = CameraModel(
            engine: engine, store: InMemoryCameraSettingsStore(settings), isSurprise: false,
            microphoneStatus: { .denied }, onCapture: { results.append($0) }
        )
        await model.start()
        async let recording: Void = model.shutter()
        while await !engine.isRecording { try await Task.sleep(for: .milliseconds(20)) }
        await engine.simulateInterruption(.anotherApp)
        await recording
        guard case let .video(video) = try #require(results.first).media else { Issue.record("not a video"); return }
        #expect(video.interruption == .anotherApp)
        results.first?.discardFiles()

        // The shutter waits for the camera to come back.
        for _ in 0..<50 where model.interruption == nil { try await Task.sleep(for: .milliseconds(20)) }
        #expect(model.interruption == .anotherApp)
        #expect(!model.canCapture)
        await engine.simulateInterruptionEnded()
        for _ in 0..<50 where model.interruption != nil { try await Task.sleep(for: .milliseconds(20)) }
        #expect(model.canCapture)
    }
}

@MainActor
struct CameraNoticeTests {
    private func camera(
        engine: any CaptureEngine = SimulatedCaptureEngine(), mode: CameraSettings.Mode = .video,
        sound: Bool = true, microphone: PermissionStatus = .granted
    ) async -> CameraModel {
        var settings = CameraSettings()
        settings.opensIn = mode
        settings.recordsSound = sound
        let model = CameraModel(
            engine: engine, store: InMemoryCameraSettingsStore(settings), isSurprise: false,
            microphoneStatus: { microphone }, onCapture: { $0.discardFiles() }
        )
        await model.start()
        return model
    }

    @Test func aDeniedMicrophoneIsExplainedOnlyWhenItMatters() async {
        #expect(await camera(microphone: .denied).notice == .microphoneOff)
        #expect(await camera(microphone: .restricted).notice == .microphoneOff)
        #expect(await camera(sound: false, microphone: .denied).notice == nil)
        #expect(await camera(mode: .photo, microphone: .denied).notice == nil)
        #expect(await camera(microphone: .notDetermined).notice == nil)
    }

    @Test func noRoomToRecordIsExplained() async {
        let model = await camera(engine: SimulatedCaptureEngine(freeBytes: 100_000_000))
        await model.shutter()
        #expect(model.notice == .lowStorage)
        #expect(model.phase == .ready)
    }

    @Test func aCameraThatCannotStartIsExplained() async {
        let model = await camera(engine: AVCaptureEngine())
        #expect(model.notice == .unavailable)
        #expect(!model.canCapture)
    }

    @Test func interruptionsOutrankTheMicrophone() async throws {
        let engine = SimulatedCaptureEngine()
        let model = await camera(engine: engine, microphone: .denied)
        await engine.simulateInterruption(.tooWarm)
        for _ in 0..<50 where model.interruption == nil { try await Task.sleep(for: .milliseconds(20)) }
        #expect(model.notice == .interrupted(.tooWarm))
    }
}

struct MediaCheckTests {
    private func file(_ ext: String, _ bytes: [UInt8] = Array("not media".utf8)) throws -> URL {
        let url = try CaptureFiles.temporaryURL(ext)
        try Data(bytes).write(to: url)
        return url
    }

    private func goodPhoto() async throws -> CapturedPhoto {
        let engine = SimulatedCaptureEngine()
        _ = await engine.start()
        return try await engine.capturePhoto(flash: false, silent: true)
    }

    @Test func anUnreadableMainPhotoIsRejectedAndDeleted() async throws {
        let good = try await goodPhoto()
        let broken = CapturedPhoto(mainURL: try file("jpg"), mainPosition: .back, selfieURL: good.selfieURL)
        #expect(MediaCheck.checked(broken) == nil)
        #expect(!FileManager.default.fileExists(atPath: broken.mainURL.path))
        #expect(!FileManager.default.fileExists(atPath: try #require(good.selfieURL).path))
        try? FileManager.default.removeItem(at: good.mainURL)
    }

    @Test func anUnreadableSelfieIsDroppedAndTheMomentKept() async throws {
        let good = try await goodPhoto()
        let broken = try file("jpg")
        let photo = try #require(MediaCheck.checked(CapturedPhoto(mainURL: good.mainURL, mainPosition: .back, selfieURL: broken)))
        #expect(photo.selfieURL == nil)
        #expect(!FileManager.default.fileExists(atPath: broken.path))
        [good.mainURL, good.selfieURL].compactMap(\.self).forEach { try? FileManager.default.removeItem(at: $0) }
    }

    @Test func anEmptyVideoIsRejected() async throws {
        let empty = CapturedVideo(mainURL: try file("mov", []), mainPosition: .back, selfieURL: nil, duration: 0, selfieOffset: 0, hasAudio: false)
        #expect(await MediaCheck.checked(empty) == nil)
        #expect(!FileManager.default.fileExists(atPath: empty.mainURL.path))
    }

    @Test func aRecordedVideoPasses() async throws {
        let engine = SimulatedCaptureEngine()
        _ = await engine.start()
        let video = try await engine.record(limit: .seconds(1))
        let checked = try #require(await MediaCheck.checked(video))
        #expect(checked == video)
        [video.mainURL, video.selfieURL].compactMap(\.self).forEach { try? FileManager.default.removeItem(at: $0) }
    }
}
