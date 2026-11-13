@testable import AppFeature
@testable import Core
import Foundation
import Testing

/// 7.1: review (C07) and the interrupted clip (C13d) on simulated captures.
@MainActor
struct ReviewModelTests {
    private let time = CaptureTime(instant: Date(timeIntervalSince1970: 1_000), timeZone: .gmt)

    private func photo(selfie: Bool = true, window: CameraSettings.SelfieWindow? = .init(corner: .bottomLeft)) async throws -> ReviewModel {
        var photo = try await started(multiCam: selfie).capturePhoto(flash: false, silent: true)
        if !selfie { photo.selfieURL = nil }
        return ReviewModel(capture: CaptureResult(media: .photo(photo), window: selfie ? window : nil, capturedAt: time))
    }

    private func video(interruption: CaptureInterruption? = nil) async throws -> ReviewModel {
        var video = try await started().record(limit: .seconds(1))
        video.interruption = interruption
        return ReviewModel(capture: CaptureResult(media: .video(video), window: .init(), capturedAt: time))
    }

    private func started(multiCam: Bool = true) async -> SimulatedCaptureEngine {
        let engine = SimulatedCaptureEngine(multiCam: multiCam)
        _ = await engine.start()
        return engine
    }

    @Test func startsWithTheWindowWhereItWasCaptured() async throws {
        let review = try await photo()
        defer { review.discard() }
        #expect(review.window.corner == .bottomLeft)
        #expect(review.hasSelfie)
        #expect(review.video == nil && review.interruption == nil)
    }

    @Test func movingTheWindowInReviewLeavesTheCameraDefault() async throws {
        let store = InMemoryCameraSettingsStore()
        let review = try await photo(window: store.load().selfieWindow)
        defer { review.discard() }
        review.window.corner = .bottomRight
        #expect(store.load().selfieWindow.corner == .topRight)
    }

    @Test func theCaptionIsOneShortLine() async throws {
        let review = try await photo()
        defer { review.discard() }
        review.caption = String(repeating: "a", count: 100)
        #expect(review.caption.count == ReviewModel.captionLimit)
        review.caption = "Lena on her bike"
        #expect(review.caption == "Lena on her bike")
    }

    @Test func loadsUprightStillsAtTheCapturedShape() async throws {
        let review = try await photo()
        defer { review.discard() }
        await review.load()
        #expect(review.main?.size == CGSize(width: 900, height: 1200))
        #expect(review.selfie != nil)
        #expect(abs(review.aspectRatio - 0.75) < 0.001)
    }

    @Test func aVideoShowsItsFirstFramesAndPlaysComposed() async throws {
        let review = try await video()
        defer { review.discard() }
        await review.load()
        #expect(review.main != nil && review.selfie != nil)
        #expect(review.playback == .stopped)
        review.windowFrame = SelfieWindowFrame(frame: CGRect(x: 270, y: 110, width: 112, height: 150), preview: CGSize(width: 402, height: 536))
        await review.togglePlayback()
        #expect(review.playback == .playing)
        #expect(review.player.currentItem?.videoComposition != nil)
        await review.togglePlayback()
        #expect(review.playback == .paused)
        await review.togglePlayback()
        #expect(review.playback == .playing)
        review.stopPlayback()
        #expect(review.playback == .stopped && review.player.currentItem == nil)
    }

    @Test func theSavedTimingCarriesTheReviewWindow() async throws {
        let review = try await video()
        defer { review.discard() }
        let frame = SelfieWindowFrame(frame: CGRect(x: 8.7, y: 300, width: 140, height: 187.5), preview: CGSize(width: 402, height: 536))
        review.windowFrame = frame
        let video = try #require(review.video)
        #expect(review.timing(video).window == frame)
        #expect(review.timing(video).duration == video.duration)
    }

    @Test func anInterruptedClipSavesWholeSeconds() async throws {
        let review = try await video(interruption: .anotherApp)
        defer { review.discard() }
        #expect(review.interruption == .anotherApp)
        #expect(review.keptSeconds == 1)
    }

    @Test func retakeDropsEveryFile() async throws {
        let review = try await photo()
        let urls = [review.capture.mainURL, review.capture.selfieURL].compactMap(\.self)
        #expect(urls.count == 2)
        review.discard()
        #expect(urls.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
    }
}
