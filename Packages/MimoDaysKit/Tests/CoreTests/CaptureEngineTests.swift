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
        let photo = try await engine.capturePhoto(flash: false)
        #expect(photo.mainPosition == .back)
        #expect(try pixelSize(photo.mainURL) == CGSize(width: 900, height: 1200))
        #expect(try pixelSize(try #require(photo.selfieURL)) == CGSize(width: 360, height: 480))
    }

    @Test func singleSetupStartsOnTheRearAndFlips() async throws {
        let engine = SimulatedCaptureEngine(multiCam: false)
        #expect(await engine.start() == .single(.back))
        #expect(try await engine.flip() == .single(.front))
        let photo = try await engine.capturePhoto(flash: true)
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
        await #expect(throws: CaptureError.notRunning) { try await engine.capturePhoto(flash: false) }
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
        try await Task.sleep(for: .milliseconds(300))
        await engine.stopRecording()
        let clip = try await video
        #expect(clip.duration < 2)
        #expect(clip.selfieURL == nil)
    }

    @Test func oneRecordingAtATime() async throws {
        let engine = SimulatedCaptureEngine()
        _ = await engine.start()
        async let first = engine.record(limit: .seconds(1))
        try await Task.sleep(for: .milliseconds(100))
        await #expect(throws: CaptureError.alreadyRecording) { try await engine.record(limit: nil) }
        _ = try await first
    }
}

struct AVCaptureEngineTests {
    /// The simulator has no cameras: starting reports it instead of crashing.
    @Test @MainActor func startWithoutCamerasFails() async {
        let engine = AVCaptureEngine()
        await #expect(throws: CaptureError.cameraUnavailable) { try await engine.start() }
        await #expect(throws: CaptureError.notRunning) { try await engine.capturePhoto(flash: false) }
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
        #expect(try await engine.capturePhoto(flash: false).selfieURL == nil)
    }
}
