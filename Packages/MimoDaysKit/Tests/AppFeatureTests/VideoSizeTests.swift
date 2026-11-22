@testable import AppFeature
@testable import Core
import Foundation
import Testing

/// P3.4: the video size setting, what it measures, and the camera taking it between takes.
@MainActor
struct VideoSizeTests {
    @Test func theSizesSetWidthAndBitRate() {
        #expect(VideoSize.high.maxFormatWidth == 1920 && VideoSize.high.averageBitRate == nil)
        #expect(VideoSize.balanced.maxFormatWidth == 1920)
        #expect(VideoSize.compact.maxFormatWidth == 1280)
        let rates = VideoSize.allCases.compactMap(\.averageBitRate)
        #expect(rates == rates.sorted(by: >), "Smaller sizes ask for less")
    }

    @Test func nothingIsShownBeforeEnoughIsMeasured() {
        let meter = VideoSizeMeter(defaults: nil)
        #expect(meter.rate(for: .high) == nil)
        meter.record(.high, streams: 2, bytes: 5_000_000, seconds: 3)
        #expect(meter.rate(for: .high) == nil)
    }

    @Test func theRateIsTheAverageOfEveryTake() {
        let meter = VideoSizeMeter(defaults: nil)
        // 60 MB over 30 s and 50 MB over 30 s: 110 MB a minute.
        meter.record(.high, streams: 2, bytes: 60_000_000, seconds: 30)
        meter.record(.high, streams: 2, bytes: 50_000_000, seconds: 30)
        #expect(meter.rate(for: .high) == .init(megabytesPerMinute: 110, bothCameras: true))
        #expect(meter.rate(for: .compact) == nil)
    }

    /// Most videos have both cameras: that rate wins once there is one; one camera stands in until then.
    @Test func bothCamerasComeFirst() {
        let meter = VideoSizeMeter(defaults: nil)
        meter.record(.balanced, streams: 1, bytes: 20_000_000, seconds: 20)
        #expect(meter.rate(for: .balanced) == .init(megabytesPerMinute: 60, bothCameras: false))
        meter.record(.balanced, streams: 2, bytes: 40_000_000, seconds: 20)
        #expect(meter.rate(for: .balanced) == .init(megabytesPerMinute: 120, bothCameras: true))
    }

    @Test func measuresSurviveARelaunch() throws {
        let suite = "VideoSizeMeterTests"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        VideoSizeMeter(defaults: defaults).record(.compact, streams: 2, bytes: 30_000_000, seconds: 60)
        #expect(VideoSizeMeter(defaults: defaults).rate(for: .compact)?.megabytesPerMinute == 30)
        defaults.removePersistentDomain(forName: suite)
    }

    @Test func emptyTakesAreIgnored() {
        let meter = VideoSizeMeter(defaults: nil)
        meter.record(.high, streams: 2, bytes: 0, seconds: 30)
        meter.record(.high, streams: 2, bytes: 10, seconds: 0)
        #expect(meter.rates().isEmpty)
    }

    /// X02: a size chosen in the camera's ••• sheet reaches the running camera, once per change.
    @Test func theCameraTakesANewSizeBetweenTakes() async {
        let engine = SimulatedCaptureEngine()
        let model = CameraModel(
            engine: engine, store: InMemoryCameraSettingsStore(), isSurprise: false,
            microphoneStatus: { .granted }, onCapture: { _ in }
        )
        await model.start()
        model.settings.videoSize = .compact
        model.settings.videoLength = .long
        model.settings.videoSize = .balanced
        for _ in 0..<50 where await engine.videoSizes.count < 2 { try? await Task.sleep(for: .milliseconds(20)) }
        #expect(await engine.videoSizes == [.compact, .balanced])
    }

    /// Each video taken counts toward the size it was taken at.
    @Test func aVideoTakenIsMeasured() async throws {
        let engine = SimulatedCaptureEngine()
        var settings = CameraSettings()
        settings.opensIn = .video
        settings.videoSize = .compact
        var taken: [CaptureResult] = []
        let model = CameraModel(
            engine: engine, store: InMemoryCameraSettingsStore(settings), isSurprise: false,
            microphoneStatus: { .granted }, onCapture: { taken.append($0) }
        )
        let meter = VideoSizeMeter(defaults: nil)
        model.videoSizes = meter
        await model.start()
        async let recording: Void = model.shutter()
        while await !engine.isRecording { try await Task.sleep(for: .milliseconds(20)) }
        try await Task.sleep(for: .milliseconds(300))
        await model.shutter()
        await recording
        #expect(taken.count == 1)
        #expect(meter.measuredSeconds(.compact) > 0)
        #expect(meter.measuredSeconds(.high) == 0)
        taken.forEach { $0.discardFiles() }
    }
}
