import AVFoundation
@testable import Core
import Foundation
import ImageIO
import Testing

struct SimulatedCaptureEngineTests {
    private func pixelSize(_ url: URL) throws -> CGSize {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        return CGSize(width: properties[kCGImagePropertyPixelWidth] as? Int ?? 0, height: properties[kCGImagePropertyPixelHeight] as? Int ?? 0)
    }

    @Test func dualSetupCapturesBothCameras() async throws {
        let engine = SimulatedCaptureEngine()
        #expect(await engine.start() == .dual)
        let photo = try await engine.capturePhoto(flash: false, silent: false)
        #expect(photo.mainPosition == .back)
        #expect(try pixelSize(photo.mainURL) == CGSize(width: 900, height: 1200))
        #expect(try pixelSize(try #require(photo.selfieURL)) == CGSize(width: 360, height: 480))
    }

    @Test func singleSetupStartsOnTheRearAndFlips() async throws {
        let engine = SimulatedCaptureEngine(multiCam: false)
        #expect(await engine.start() == .single(.back))
        #expect(try await engine.flip() == .single(.front))
        let photo = try await engine.capturePhoto(flash: true, silent: true)
        #expect(photo.mainPosition == .front)
        #expect(photo.selfieURL == nil)
        #expect(try await engine.flip() == .single(.back))
    }

    @Test func dualSetupDoesNotFlip() async throws {
        let engine = SimulatedCaptureEngine()
        _ = await engine.start()
        #expect(try await engine.flip() == .dual)
    }

    @Test func nothingIsCapturedBeforeStartOrAfterStop() async {
        let engine = SimulatedCaptureEngine()
        await #expect(throws: CaptureError.notRunning) { try await engine.capturePhoto(flash: false, silent: false) }
        _ = await engine.start()
        await engine.stop()
        await #expect(throws: CaptureError.notRunning) { try await engine.record(limit: .seconds(1)) }
    }

    @Test func recordingStopsAtTheLimitWithOneFilePerCamera() async throws {
        let engine = SimulatedCaptureEngine()
        _ = await engine.start()
        let video = try await engine.record(limit: .seconds(1))
        #expect(abs(video.duration - 1) < 0.2)
        for url in [video.mainURL, try #require(video.selfieURL)] {
            let duration = try await AVURLAsset(url: url).load(.duration).seconds
            #expect(abs(duration - video.duration) < 0.2)
        }
    }

    @Test func stopRecordingEndsItEarly() async throws {
        let engine = SimulatedCaptureEngine(multiCam: false)
        _ = await engine.start()
        async let video = engine.record(limit: .seconds(60))
        // A stop before the recording starts is ignored, so wait for it (slow CI runners).
        while await !engine.isRecording { try await Task.sleep(for: .milliseconds(20)) }
        await engine.stopRecording()
        let clip = try await video
        #expect(clip.duration < 10)
        #expect(clip.selfieURL == nil)
    }

    @Test func oneRecordingAtATime() async throws {
        let engine = SimulatedCaptureEngine()
        _ = await engine.start()
        async let first = engine.record(limit: .seconds(30))
        while await !engine.isRecording { try await Task.sleep(for: .milliseconds(20)) }
        await #expect(throws: CaptureError.alreadyRecording) { try await engine.record(limit: nil) }
        await engine.stopRecording()
        _ = try await first
    }
}

struct AVCaptureEngineTests {
    /// The simulator has no cameras: starting reports it instead of crashing.
    @Test @MainActor func startWithoutCamerasFails() async {
        let engine = AVCaptureEngine()
        await #expect(throws: CaptureError.cameraUnavailable) { try await engine.start() }
        await #expect(throws: CaptureError.notRunning) { try await engine.capturePhoto(flash: false, silent: false) }
        #expect(engine.previewLayer(for: .back) != nil)
    }
}

struct CapturePressurePolicyTests {
    typealias Policy = CapturePressurePolicy

    @Test(arguments: [(Policy.Level.nominal, 30), (.fair, 30), (.serious, 24), (.critical, 15), (.shutdown, 15)])
    func frameRateFallsWithPressure(level: Policy.Level, frameRate: Int) {
        #expect(Policy.response(to: level, setup: .dual, isRecording: false).frameRate == frameRate)
    }

    @Test func onlyCriticalPressureDropsTheSelfieCamera() {
        #expect(!Policy.response(to: .serious, setup: .dual, isRecording: false).dropsSelfie)
        #expect(Policy.response(to: .critical, setup: .dual, isRecording: false).dropsSelfie)
        #expect(Policy.response(to: .shutdown, setup: .dual, isRecording: false).dropsSelfie)
    }

    @Test func aRecordingIsNeverCutAndOneCameraHasNothingToDrop() {
        #expect(!Policy.response(to: .critical, setup: .dual, isRecording: true).dropsSelfie)
        #expect(!Policy.response(to: .critical, setup: .single(.front), isRecording: false).dropsSelfie)
    }

    @Test func dualFormatsStepDown() {
        #expect(Policy.dualFormatWidths == Policy.dualFormatWidths.sorted(by: >))
    }

    @Test func simulatedEngineReportsTheDroppedSelfieCamera() async throws {
        let engine = SimulatedCaptureEngine()
        _ = await engine.start()
        var events = engine.events.makeAsyncIterator()
        await engine.simulatePressure(.serious)
        await engine.simulatePressure(.critical)
        #expect(await events.next() == .setupChanged(.single(.back)))
        #expect(try await engine.capturePhoto(flash: false, silent: false).selfieURL == nil)
    }
}

struct CaptureInterruptionTests {
    @Test func storageBudgetKeepsAReserveAndASensibleMinimum() {
        #expect(CaptureStorage.budgetPerStream(freeBytes: 10_000_000_000, streams: 2) == 4_900_000_000)
        #expect(CaptureStorage.budgetPerStream(freeBytes: 250_000_000, streams: 2) == 25_000_000)
        #expect(CaptureStorage.budgetPerStream(freeBytes: 230_000_000, streams: 2) == nil)
        #expect(CaptureStorage.budgetPerStream(freeBytes: 10_000_000_000, streams: 0) == nil)
    }

    @Test func lowPowerModeLowersTheFrameRateButDropsNothing() {
        #expect(CapturePressurePolicy.response(to: .nominal, lowPower: true, setup: .dual, isRecording: false) == .init(frameRate: 24, dropsSelfie: false))
        #expect(CapturePressurePolicy.response(to: .critical, lowPower: true, setup: .dual, isRecording: false).dropsSelfie)
    }

    @Test func sessionReasonsMapToWhatThePersonSees() {
        #expect(CaptureInterruption(.videoDeviceNotAvailableInBackground) == .background)
        #expect(CaptureInterruption(.audioDeviceInUseByAnotherClient) == .anotherApp)
        #expect(CaptureInterruption(.videoDeviceInUseByAnotherClient) == .anotherApp)
        #expect(CaptureInterruption(.videoDeviceNotAvailableDueToSystemPressure) == .tooWarm)
    }

    @Test func recordingErrorsMapToInterruptions() {
        #expect(CaptureInterruption(endingRecording: AVError(.maximumDurationReached)) == nil)
        #expect(CaptureInterruption(endingRecording: AVError(.diskFull)) == .lowStorage)
        #expect(CaptureInterruption(endingRecording: AVError(.maximumFileSizeReached)) == .lowStorage)
        #expect(CaptureInterruption(endingRecording: AVError(.sessionWasInterrupted)) == .other)
    }

    @Test func anInterruptedRecordingKeepsWhatItHas() async throws {
        let engine = SimulatedCaptureEngine()
        _ = await engine.start()
        async let video = engine.record(limit: .seconds(30))
        while await !engine.isRecording { try await Task.sleep(for: .milliseconds(20)) }
        await engine.simulateInterruption(.anotherApp)
        let clip = try await video
        defer { [clip.mainURL, clip.selfieURL].compactMap(\.self).forEach { try? FileManager.default.removeItem(at: $0) } }
        #expect(clip.interruption == .anotherApp)
        #expect(clip.duration < 10)
        #expect(clip.selfieURL != nil)
        // Nothing is captured until the camera is back.
        await #expect(throws: CaptureError.notRunning) { try await engine.capturePhoto(flash: false, silent: false) }
        await engine.simulateInterruptionEnded()
        let photo = try await engine.capturePhoto(flash: false, silent: false)
        [photo.mainURL, photo.selfieURL].compactMap(\.self).forEach { try? FileManager.default.removeItem(at: $0) }
    }

    @Test func noRoomNoRecording() async {
        let engine = SimulatedCaptureEngine(freeBytes: 210_000_000)
        _ = await engine.start()
        await #expect(throws: CaptureError.lowStorage) { try await engine.record(limit: .seconds(10)) }
    }

    @Test func interruptionsAreReported() async {
        let engine = SimulatedCaptureEngine()
        _ = await engine.start()
        var events = engine.events.makeAsyncIterator()
        await engine.simulateInterruption(.background)
        await engine.simulateInterruptionEnded()
        #expect(await events.next() == .interrupted(.background))
        #expect(await events.next() == .resumed)
    }
}
