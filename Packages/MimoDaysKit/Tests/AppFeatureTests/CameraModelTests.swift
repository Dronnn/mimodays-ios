@testable import AppFeature
@testable import Core
import Foundation
import QuartzCore
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

    @Test func aRetakenCameraStillHearsInterruptions() async {
        let engine = SimulatedCaptureEngine()
        let model = await videoCamera(engine: engine, allowed: true)
        await model.stop() // Review opens
        await model.start() // Retake
        await engine.simulateInterruption(.anotherApp)
        #expect(await eventually { await MainActor.run { model.interruption == .anotherApp } })
        await engine.simulateInterruptionEnded()
        #expect(await eventually { await MainActor.run { model.interruption == nil } })
    }

    /// An error stopped the camera and nothing says it ended: back in the app, it starts again and the shutter works.
    @Test func comingBackRestartsACameraAnErrorStopped() async {
        let engine = SimulatedCaptureEngine()
        let model = await videoCamera(engine: engine, allowed: true)
        await engine.simulateInterruption(.other)
        #expect(await eventually { await MainActor.run { model.interruption == .other } })
        await model.recover()
        #expect(await eventually { await MainActor.run { model.interruption == nil && model.canCapture } })
    }

    @Test func aCallEndingWhileReviewShowsFreesTheShutter() async {
        let engine = SimulatedCaptureEngine()
        let model = await videoCamera(engine: engine, allowed: true)
        await engine.simulateInterruption(.anotherApp)
        #expect(await eventually { await MainActor.run { model.interruption == .anotherApp } })
        await model.stop() // Review opens
        await engine.simulateInterruptionEnded()
        await model.start() // Retake
        #expect(await eventually { await MainActor.run { model.interruption == nil } })
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

    /// "Record sound" off in the ••• sheet turns the microphone off.
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

    /// Swapped before recording: the front camera's file is the main one, the rear's the selfie, the offset turned round.
    @Test func aSwappedRecordingPutsTheFrontStreamFirst() async throws {
        let engine = OffsetVideoEngine()
        var results: [CaptureResult] = []
        var settings = CameraSettings()
        settings.opensIn = .video
        let model = CameraModel(
            engine: engine, store: InMemoryCameraSettingsStore(settings), isSurprise: false,
            microphoneStatus: { .denied }, onCapture: { results.append($0) }
        )
        await model.start()
        await model.flip()
        #expect(model.isSwapped)
        await model.shutter()
        guard case let .video(video) = try #require(results.first).media else { Issue.record("not a video"); return }
        let recorded = try #require(await engine.recorded)
        #expect(video.mainPosition == .front)
        #expect(video.mainURL == recorded.selfieURL)
        #expect(video.selfieURL == recorded.mainURL)
        #expect(video.selfieOffset == -0.3)
        results.first?.discardFiles()
    }

    /// The simulated recording with the selfie starting 0.3 s after the main stream.
    private actor OffsetVideoEngine: CaptureEngine {
        private let base = SimulatedCaptureEngine()
        private(set) var recorded: CapturedVideo?

        func start() async throws -> CameraSetup { try await base.start() }
        func stop() async {}
        func backLenses() async -> [BackLens] { await base.backLenses() }
        func setBackLens(_ lens: BackLens) async throws { try await base.setBackLens(lens) }
        func flip() async throws -> CameraSetup { try await base.flip() }
        func setMicrophone(_ enabled: Bool) async throws { try await base.setMicrophone(enabled) }
        func capturePhoto(flash: FlashMode, silent: Bool) async throws -> CapturedPhoto { try await base.capturePhoto(flash: flash, silent: silent) }
        func record(limit _: Duration?) async throws -> CapturedVideo {
            var video = try await base.record(limit: .milliseconds(600))
            video.selfieOffset = 0.3
            recorded = video
            return video
        }
        func stopRecording() async { await base.stopRecording() }
        func setTorch(_ mode: FlashMode) async { await base.setTorch(mode) }
        func setCaptureHold(_ hold: DeviceHold) async { await base.setCaptureHold(hold) }
        @MainActor func previewLayer(for _: CameraPosition) -> CALayer? { nil }
        @MainActor func setPreviewHold(_: DeviceHold) {}
        nonisolated var events: AsyncStream<CaptureEvent> { base.events }
    }

    /// Closed while a photo is being taken: the photo goes, and no review opens for it.
    @Test func aPhotoFinishingAfterCloseIsThrownAway() async throws {
        let engine = HeldPhotoEngine()
        var results: [CaptureResult] = []
        var settings = CameraSettings()
        settings.opensIn = .photo
        let model = CameraModel(
            engine: engine, store: InMemoryCameraSettingsStore(settings), isSurprise: false,
            microphoneStatus: { .denied }, onCapture: { results.append($0) }
        )
        await model.start()
        async let shot: Void = model.shutter()
        while await !engine.isHolding { try await Task.sleep(for: .milliseconds(10)) }
        model.close()
        await engine.release()
        await shot
        #expect(results.isEmpty)
    }

    /// What the screen showed at the shutter is the photo's: a format or selfie change during the flash is for the next.
    @Test func changesWhileThePhotoFinishesAreForTheNextOne() async throws {
        let engine = HeldPhotoEngine()
        var results: [CaptureResult] = []
        var settings = CameraSettings()
        settings.opensIn = .photo
        let model = CameraModel(
            engine: engine, store: InMemoryCameraSettingsStore(settings), isSurprise: false,
            microphoneStatus: { .denied }, onCapture: { results.append($0) }
        )
        await model.start()
        let format = model.format
        async let shot: Void = model.shutter()
        while await !engine.isHolding { try await Task.sleep(for: .milliseconds(10)) }
        model.setFormat(format == .square ? .portrait : .square)
        model.toggleSelfie()
        await engine.release()
        await shot
        let result = try #require(results.first)
        #expect(result.format == format)
        #expect(result.selfieURL != nil)
    }

    /// The simulated camera, with a photo that comes only once released and a stop that doesn't cut it short.
    private actor HeldPhotoEngine: CaptureEngine {
        private let base = SimulatedCaptureEngine()
        private var held: CheckedContinuation<Void, Never>?
        var isHolding: Bool { held != nil }
        func release() { held?.resume(); held = nil }

        func start() async throws -> CameraSetup { try await base.start() }
        func stop() async {}
        func backLenses() async -> [BackLens] { await base.backLenses() }
        func setBackLens(_ lens: BackLens) async throws { try await base.setBackLens(lens) }
        func flip() async throws -> CameraSetup { try await base.flip() }
        func setMicrophone(_ enabled: Bool) async throws { try await base.setMicrophone(enabled) }
        func capturePhoto(flash: FlashMode, silent: Bool) async throws -> CapturedPhoto {
            await withCheckedContinuation { held = $0 }
            return try await base.capturePhoto(flash: flash, silent: silent)
        }
        func record(limit: Duration?) async throws -> CapturedVideo { try await base.record(limit: limit) }
        func stopRecording() async { await base.stopRecording() }
        func setTorch(_ mode: FlashMode) async { await base.setTorch(mode) }
        func setCaptureHold(_ hold: DeviceHold) async { await base.setCaptureHold(hold) }
        @MainActor func previewLayer(for _: CameraPosition) -> CALayer? { nil }
        @MainActor func setPreviewHold(_: DeviceHold) {}
        nonisolated var events: AsyncStream<CaptureEvent> { base.events }
    }

    /// Stop tapped while the recording is still starting (here, the torch) ends it: it doesn't run to its limit.
    @Test func aStopWhileTheRecordingStartsIsKept() async throws {
        let engine = SimulatedCaptureEngine()
        var results: [CaptureResult] = []
        var settings = CameraSettings()
        settings.opensIn = .video
        settings.videoLength = .long
        settings.flash = .on
        let model = CameraModel(
            engine: engine, store: InMemoryCameraSettingsStore(settings), isSurprise: false,
            microphoneStatus: { .denied }, onCapture: { results.append($0) }
        )
        await model.start()
        async let recording: Void = model.shutter()
        while !model.isRecording { await Task.yield() }
        await model.shutter()
        await recording
        #expect(results.isEmpty && !model.isRecording)
        #expect(await !engine.isRecording)
    }

    /// 9.19: the flash button lights the rear camera while a video records, also when pressed mid-recording.
    @Test func flashLightsTheRearCameraWhileRecording() async throws {
        let engine = SimulatedCaptureEngine()
        var settings = CameraSettings()
        settings.opensIn = .video
        settings.videoLength = .long
        let model = CameraModel(
            engine: engine, store: InMemoryCameraSettingsStore(settings), isSurprise: false,
            microphoneStatus: { .denied }, onCapture: { $0.discardFiles() }
        )
        await model.start()
        model.settings.flash = .on
        async let recording: Void = model.shutter()
        while await !engine.isRecording { try await Task.sleep(for: .milliseconds(20)) }
        model.settings.flash = .off
        model.nextFlash()
        try await Task.sleep(for: .milliseconds(100))
        await engine.stopRecording()
        await recording
        #expect(await engine.torchChanges == [.on, .off, .auto, .off])
    }

    /// Sound off records no sound, also right after it was on (Andrew, 2026-11-16); sound on records it.
    @Test func eachRecordingTakesTheSoundSettingAtTheShutter() async throws {
        let engine = SimulatedCaptureEngine()
        var settings = CameraSettings()
        settings.opensIn = .video
        settings.videoLength = .long
        let model = CameraModel(
            engine: engine, store: InMemoryCameraSettingsStore(settings), isSurprise: false,
            microphoneStatus: { .granted }, onCapture: { $0.discardFiles() }
        )
        await model.start()
        for sound in [false, true, false] {
            model.toggleSound()
            #expect(model.microphoneOn == sound)
            async let recording: Void = model.shutter()
            while await !engine.isRecording { try await Task.sleep(for: .milliseconds(20)) }
            #expect(await engine.hasMicrophone == sound)
            await engine.stopRecording()
            await recording
        }
    }

    /// The ••• sheet's rear lens reaches the camera when it opens and when it changes (Andrew, 2026-11-16).
    @Test func theChosenBackLensFilms() async throws {
        let engine = SimulatedCaptureEngine(lenses: [.ultraWide, .wide, .telephoto])
        var settings = CameraSettings()
        settings.backLens = .ultraWide
        let model = CameraModel(
            engine: engine, store: InMemoryCameraSettingsStore(settings), isSurprise: false,
            microphoneStatus: { .denied }, onCapture: { $0.discardFiles() }
        )
        await model.start()
        #expect(model.lenses == [.ultraWide, .wide, .telephoto])
        #expect(await engine.backLens == .ultraWide)
        model.settings.backLens = .telephoto
        for _ in 0..<50 where await engine.backLens != .telephoto { try await Task.sleep(for: .milliseconds(20)) }
        #expect(await engine.backLens == .telephoto)
    }

    /// The flash button goes off, auto, on and round again, and the camera remembers it (Andrew, 2026-11-16).
    @Test func flashButtonGoesRoundItsThreeModes() {
        let store = InMemoryCameraSettingsStore()
        let model = CameraModel(
            engine: SimulatedCaptureEngine(), store: store, isSurprise: false,
            microphoneStatus: { .denied }, onCapture: { $0.discardFiles() }
        )
        var seen = [model.settings.flash]
        for _ in 0..<3 {
            model.nextFlash()
            seen.append(model.settings.flash)
        }
        #expect(seen == [.off, .auto, .on, .off])
        model.nextFlash()
        #expect(store.load().flash == .auto)
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
        return try await engine.capturePhoto(flash: .off, silent: true)
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

    /// A photo cut off part-way (its size still reads) isn't a moment.
    @Test func aCutOffPhotoIsRejected() async throws {
        let good = try await goodPhoto()
        let data = try Data(contentsOf: good.mainURL)
        let cut = try file("jpg", Array(data.prefix(data.count / 2)))
        #expect(!MediaCheck.isReadableImage(cut))
        #expect(MediaCheck.isReadableImage(good.mainURL))
        [cut, good.mainURL, good.selfieURL].compactMap(\.self).forEach { try? FileManager.default.removeItem(at: $0) }
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
        var expected = video
        expected.duration = checked.duration
        #expect(checked == expected)
        #expect(abs(checked.duration - video.duration) < 0.2)
        [video.mainURL, video.selfieURL].compactMap(\.self).forEach { try? FileManager.default.removeItem(at: $0) }
    }

    /// After a swap the main file is the selfie camera's, which can be shorter: the moment takes that file's length.
    @Test func aSwappedVideoTakesItsMainFilesLength() async throws {
        let engine = SimulatedCaptureEngine()
        _ = await engine.start()
        var video = try await engine.record(limit: .seconds(1))
        let actual = video.duration
        video.duration = actual + 5
        let checked = try #require(await MediaCheck.checked(video))
        #expect(abs(checked.duration - actual) < 0.2)
        [video.mainURL, video.selfieURL].compactMap(\.self).forEach { try? FileManager.default.removeItem(at: $0) }
    }
}

/// P1: zoom stops, pinch and tap to focus on the simulated camera (a rear camera at 0.5×, 1×, 2×).
@MainActor
struct CameraZoomFocusTests {
    private func camera(lenses: [BackLens] = [.ultraWide, .wide, .telephoto]) async -> (CameraModel, SimulatedCaptureEngine) {
        let engine = SimulatedCaptureEngine(lenses: lenses)
        let model = CameraModel(
            engine: engine, store: InMemoryCameraSettingsStore(), isSurprise: false,
            microphoneStatus: { .denied }, onCapture: { _ in }
        )
        await model.start()
        return (model, engine)
    }

    private func settle(_ engine: SimulatedCaptureEngine, _ position: CameraPosition, at factor: Double) async throws {
        for _ in 0..<50 where await engine.zoomFactors[position] != factor { try await Task.sleep(for: .milliseconds(10)) }
    }

    @Test func theCameraOpensAtTheChosenLens() async throws {
        let (model, _) = await camera()
        let zoom = try #require(model.mainZoom)
        #expect(zoom.stops == [1, 2, 4])
        #expect(zoom.shown == 1)
        #expect(ZoomLabel.text(zoom.shown).hasPrefix("1"))
    }

    @Test func theLabelStepsThroughTheLensesAndRoundAgain() async throws {
        let (model, engine) = await camera()
        model.nextZoomStop()
        #expect(model.mainZoom?.shown == 2)
        #expect(model.settings.backLens == .telephoto)
        try await settle(engine, .back, at: 4)
        model.nextZoomStop()
        #expect(model.mainZoom?.shown == 0.5)
        #expect(model.settings.backLens == .ultraWide)
        try await settle(engine, .back, at: 1)
        #expect(await engine.zoomFactors[.back] == 1)
    }

    @Test func aPinchZoomsFromWhereItBeganAndStopsAtTheEnds() async throws {
        let (model, engine) = await camera()
        model.pinch(1.5, on: .back, ended: false)
        model.pinch(2, on: .back, ended: true)
        #expect(model.mainZoom?.factor == 4)
        try await settle(engine, .back, at: 4)
        model.pinch(100, on: .back, ended: true)
        #expect(model.mainZoom?.shown == CameraZoom.maxShown)
        model.pinch(0.01, on: .back, ended: true)
        #expect(model.mainZoom?.factor == 1)
        try await settle(engine, .back, at: 1)
    }

    /// Swapped, the label and a pinch are the front camera's; the rear keeps its own zoom.
    @Test func frontAndRearZoomStayApart() async throws {
        let (model, engine) = await camera()
        await model.flip()
        #expect(model.mainZoom?.stops == [1])
        model.pinch(2, on: .front, ended: true)
        try await settle(engine, .front, at: 2)
        #expect(model.zooms[.back]?.shown == 1)
    }

    /// Pinches on both cameras at once: neither is lost on the way to the camera.
    @Test func pinchesOnBothCamerasBothArrive() async throws {
        let (model, engine) = await camera()
        model.pinch(2, on: .back, ended: true)
        model.pinch(2, on: .front, ended: true)
        try await settle(engine, .back, at: 4)
        try await settle(engine, .front, at: 2)
        #expect(await engine.zoomFactors[.back] == 4)
        #expect(await engine.zoomFactors[.front] == 2)
    }

    /// Retake opens the camera where the shot was framed: the saved lens is only for the first start.
    @Test func aRetakeKeepsThePinchedZoom() async throws {
        let (model, engine) = await camera()
        model.pinch(2, on: .back, ended: true)
        try await settle(engine, .back, at: 4)
        await model.stop()
        await model.start()
        #expect(await engine.zoomFactors[.back] == 4)
    }

    /// Pinched away from the chosen lens, choosing it again in ••• goes back to it.
    @Test func choosingTheSameLensAfterAPinchGoesBackToIt() async throws {
        let (model, engine) = await camera()
        model.pinch(2, on: .back, ended: true)
        try await settle(engine, .back, at: 4)
        model.chooseBackLens(.wide)
        try await settle(engine, .back, at: 2)
        #expect(await engine.zoomFactors[.back] == 2)
        #expect(model.settings.backLens == .wide)
    }

    /// A swap moves the picture the lock was on, so the lock goes: no camera stays held without its mark.
    @Test func aSwapReleasesALock() async throws {
        let (model, engine) = await camera()
        await model.focus(at: CGPoint(x: 0.2, y: 0.2), layerPoint: .zero, on: .back, lock: true)
        await model.flip()
        #expect(model.focusMark == nil)
        #expect(await engine.focusTaps.last.map { $0.position == .back && !$0.lock } == true)
    }

    /// A lock on the rear camera, then a tap on the front one: the swap still lets the rear go, though the mark moved.
    @Test func aSwapReleasesEveryLock() async throws {
        let (model, engine) = await camera()
        await model.focus(at: CGPoint(x: 0.2, y: 0.2), layerPoint: .zero, on: .back, lock: true)
        await model.focus(at: CGPoint(x: 0.6, y: 0.6), layerPoint: .zero, on: .front, lock: false)
        await model.flip()
        let afterSwap = await engine.focusTaps.dropFirst(2)
        #expect(afterSwap.contains { $0.position == .back && !$0.lock })
        #expect(!afterSwap.contains { $0.position == .front })
    }

    @Test func aTapFocusesThereAndTheMarkFades() async throws {
        let (model, engine) = await camera()
        await model.focus(at: CGPoint(x: 0.2, y: 0.3), layerPoint: CGPoint(x: 40, y: 90), on: .back, lock: false)
        let mark = try #require(model.focusMark)
        #expect(mark.point == CGPoint(x: 40, y: 90))
        #expect(mark.result == FocusResult(focuses: true, exposes: true, locks: false))
        #expect(await engine.focusTaps.last?.point == CGPoint(x: 0.2, y: 0.3))
        model.focusMarkFaded(mark)
        #expect(model.focusMark == nil)
    }

    @Test func aLongPressLocksAndTheLockStaysUntilTheNextTap() async throws {
        let (model, engine) = await camera()
        await model.focus(at: CGPoint(x: 0.5, y: 0.5), layerPoint: .zero, on: .front, lock: true)
        let mark = try #require(model.focusMark)
        #expect(mark.result == FocusResult(focuses: false, exposes: true, locks: true))
        model.focusMarkFaded(mark)
        #expect(model.focusMark == mark)
        await model.focus(at: CGPoint(x: 0.1, y: 0.1), layerPoint: .zero, on: .front, lock: false)
        #expect(model.focusMark?.result.locks == false)
        #expect(await engine.focusTaps.map(\.lock) == [true, false])
    }

    @Test func zoomStopsGoRoundAndKnowWhereTheyAre() {
        let zoom = CameraZoom(stops: [1, 2, 6], minFactor: 1, maxFactor: 20, shownMultiplier: 0.5, factor: 2.5)
        #expect(zoom.currentStop == nil)
        #expect(zoom.nextStop == 6)
        #expect(CameraZoom(stops: [1, 2, 6], minFactor: 1, maxFactor: 20, shownMultiplier: 0.5, factor: 6).nextStop == 1)
        #expect(zoom.clamped(40) == 20)
        #expect(ZoomLabel.text(1.25) == "1.3×" || ZoomLabel.text(1.25) == "1.2×")
    }
}

struct SelfieWindowPinchTests {
    @Test func aPinchChangesTheWindowByOneSize() {
        typealias Scale = CameraSettings.SelfieWindow.Scale
        #expect(Scale.medium.after(pinch: 1.5) == .large)
        #expect(Scale.large.after(pinch: 2) == .large)
        #expect(Scale.medium.after(pinch: 0.6) == .small)
        #expect(Scale.small.after(pinch: 0.5) == .small)
        #expect(Scale.medium.after(pinch: 1.05) == .medium)
    }
}
