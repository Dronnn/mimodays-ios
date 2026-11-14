@preconcurrency import AVFoundation
@testable import AppFeature
@testable import Core
import Foundation
import Persistence
import SwiftData
import Testing
import TestSupport

/// 11.7 A project plays as one movie: clips back to back, the picture fitted to the movie's shape, the selfie window
/// on the movie's frame, captions, fades, clip sound and voice notes.
@MainActor
struct MovieComposerTests {
    private let container = try! MimoDaysStore.makeContainer(inMemory: true)
    private let store: MediaStore
    private let now = Date(timeIntervalSince1970: 1_794_398_400) // Nov 11, 2026, noon UTC

    init() throws {
        store = try MediaStore(root: FileManager.default.temporaryDirectory.appending(path: "MovieComposer-\(UUID().uuidString)"))
    }

    private var context: ModelContext { container.mainContext }
    private var movies: MovieStore { MovieStore(context: context, store: store, now: { [now] in now }) }
    private let portrait = MovieAspectRatio.portrait9x16.renderSize(.p720)

    /// Simulated-camera moments, both cameras; `videos` indexes are 1 s videos.
    private func save(_ count: Int, videos: Set<Int> = []) async throws -> [UUID] {
        let engine = SimulatedCaptureEngine()
        _ = await engine.start()
        let saver = MomentSaver(context: context, store: store, clock: TestDateProvider(), freeBytes: { nil })
        var ids: [UUID] = []
        for index in 0..<count {
            let media: CaptureResult.Media = videos.contains(index)
                ? .video(try await engine.record(limit: .seconds(1)))
                : .photo(try await engine.capturePhoto(flash: false, silent: true))
            let capture = CaptureResult(media: media, window: .init(), capturedAt: CaptureTime(instant: now, timeZone: .gmt))
            let draft = MomentDraft(
                capture: capture, caption: "",
                window: SelfieWindowFrame(frame: CGRect(x: 266.7, y: 111.1, width: 112, height: 150), preview: CGSize(width: 402, height: 536)),
                promptID: nil
            )
            ids.append(try await saver.save(draft).id)
        }
        return ids
    }

    private func project(_ ids: [UUID], shape: MovieAspectRatio = .portrait9x16, fit: MovieFit = .fill) throws -> MovieProject {
        try movies.create(title: "Test", source: MovieSourceRule(kind: .selection), length: .full, aspectRatio: shape, fit: fit, momentIDs: ids)
    }

    private func frame(_ composed: MovieComposer.Composed, at seconds: Double) async throws -> CGImage {
        let generator = AVAssetImageGenerator(asset: composed.asset)
        generator.videoComposition = composed.videoComposition
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        return try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image
    }

    /// RGB at a point counted from the top left.
    private func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int) {
        var data = [UInt8](repeating: 0, count: 4)
        let context = CGContext(
            data: &data, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
        return (Int(data[0]), Int(data[1]), Int(data[2]))
    }

    private func brightness(_ image: CGImage, _ x: Int, _ y: Int) -> Int {
        let p = pixel(image, x, y)
        return max(p.r, p.g, p.b)
    }

    // MARK: Layout

    @Test func fillCoversTheFrameAndShowAllFitsInside() {
        let canvas = CGSize(width: 1920, height: 1080)
        let source = CGSize(width: 900, height: 1200)
        #expect(MovieComposer.pictureRect(source: source, canvas: canvas, fit: .fill) == CGRect(x: 0, y: -740, width: 1920, height: 2560))
        #expect(MovieComposer.pictureRect(source: source, canvas: canvas, fit: .showAll) == CGRect(x: 555, y: 0, width: 810, height: 1080))
    }

    @Test func theWindowSitsWhereF07SaysAndStaysInsideTheFrame() throws {
        let canvas = CGSize(width: 1080, height: 1920)
        let picture = CGRect(origin: .zero, size: canvas)
        let margin = 1080 * MovieComposer.marginScale
        let right = try #require(MovieComposer.windowRect(window: nil, placement: .topRight, picture: picture, canvas: canvas))
        #expect(abs(right.maxX - (1080 - margin)) < 0.01 && abs(right.minY - margin) < 0.01)
        #expect(abs(right.width - 1080 * 112 / 402) < 0.01)
        let bottom = try #require(MovieComposer.windowRect(window: nil, placement: .bottom, picture: picture, canvas: canvas))
        #expect(abs(bottom.maxY - (1920 - margin)) < 0.01 && abs(bottom.maxX - (1080 - margin)) < 0.01)
        #expect(MovieComposer.windowRect(window: nil, placement: .hidden, picture: picture, canvas: canvas) == nil)
        // Recorded in the top right corner of a picture that Fill pushes past the frame: kept inside it.
        let wide = CGSize(width: 1920, height: 1080)
        let filled = MovieComposer.pictureRect(source: CGSize(width: 900, height: 1200), canvas: wide, fit: .fill)
        let kept = try #require(MovieComposer.windowRect(window: PiPLayout(centerX: 0.8, centerY: 0.1, scale: 0.28), placement: nil, picture: filled, canvas: wide))
        #expect(kept.minY >= 1080 * MovieComposer.marginScale - 0.01)
        #expect(kept.maxX <= 1920 - 1080 * MovieComposer.marginScale + 0.01)
    }

    @Test func aLateSelfieStartsLaterAndAnEarlyOneIsTrimmed() throws {
        let late = try #require(MovieComposer.selfiePart(mainStart: 0, length: 2, offset: 0.5, selfieLength: 3))
        #expect(late.0.start.seconds == 0 && abs(late.0.duration.seconds - 1.5) < 0.01 && abs(late.1.seconds - 0.5) < 0.01)
        let early = try #require(MovieComposer.selfiePart(mainStart: 1, length: 2, offset: -0.5, selfieLength: 4))
        #expect(abs(early.0.start.seconds - 1.5) < 0.01 && abs(early.0.duration.seconds - 2) < 0.01 && early.1.seconds == 0)
        #expect(MovieComposer.selfiePart(mainStart: 0, length: 1, offset: 2, selfieLength: 3) == nil)
    }

    // MARK: Plan

    @Test func thePlanTimesPhotosAndVideosAndCaptionsThem() async throws {
        let ids = try await save(3, videos: [1])
        let project = try project(ids)
        project.showsPlaces = false
        project.orderedClips[2].clipAudio = .muted
        let plan = MoviePlan(project, store: store)
        #expect(plan.clips.map(\.momentID) == ids)
        #expect(plan.clips[0].duration == MovieSelection.photoSeconds)
        #expect(plan.clips[1].duration > 0.9 && plan.clips[1].duration < 1.2, "the 1 s video at 10 fps: \(plan.clips[1].duration)")
        #expect(plan.clips[0].caption == "Nov 11, 2026")
        #expect(plan.clips[0].selfieURL != nil && plan.clips[0].window != nil)
        #expect(!plan.clips[2].soundOn)

        let moment = try #require(project.orderedClips[0].moment)
        moment.deletedAt = now
        #expect(MoviePlan(project, store: store).clips.map(\.momentID) == Array(ids.dropFirst()))
    }

    // MARK: Composition

    @Test func theMoviePlaysEveryClipInTurnAtItsShape() async throws {
        let ids = try await save(3, videos: [1])
        let plan = MoviePlan(try project(ids), store: store)
        let composed = try await MovieComposer.compose(plan, renderSize: portrait)
        #expect(abs(composed.asset.duration.seconds - plan.duration) < 0.01)
        // Main stream and the video's selfie stream; no sound anywhere.
        #expect(composed.asset.tracks(withMediaType: .video).count == 2)
        #expect(composed.asset.tracks(withMediaType: .audio).isEmpty)

        let photo = try await frame(composed, at: 1)
        #expect(photo.width == 720 && photo.height == 1280)
        let warm = pixel(photo, 100, 1000)
        #expect(warm.r > 150 && warm.r > warm.b, "the rear photo fills the frame: \(warm)")
        let video = try await frame(composed, at: 2.5 + 0.5)
        #expect(brightness(video, 100, 1000) > 100, "the video's frames are drawn")
    }

    @Test func aFadeDipsThroughBlack() async throws {
        let ids = try await save(2)
        let project = try project(ids)
        project.orderedClips[1].transition = .fade
        let composed = try await MovieComposer.compose(MoviePlan(project, store: store), renderSize: portrait)
        let full = brightness(try await frame(composed, at: 1), 360, 900)
        let fading = brightness(try await frame(composed, at: 2.5 - MovieComposer.fadeSeconds / 2), 360, 900)
        let cut = brightness(try await frame(composed, at: 2.5), 360, 900)
        let after = brightness(try await frame(composed, at: 2.5 + 0.6), 360, 900)
        #expect(cut < 20, "black at the cut")
        #expect(fading > cut && fading < full, "half way out: \(fading) of \(full)")
        #expect(after > 150)
    }

    @Test func showAllLeavesBarsWhereFillCrops() async throws {
        let ids = try await save(1)
        let wide = MovieAspectRatio.landscape16x9.renderSize(.p720)
        let fitted = try await MovieComposer.compose(MoviePlan(try project(ids, shape: .landscape16x9, fit: .showAll), store: store), renderSize: wide)
        #expect(brightness(try await frame(fitted, at: 1), 20, 360) < 10)
        let filled = try await MovieComposer.compose(MoviePlan(try project(ids, shape: .landscape16x9, fit: .fill), store: store), renderSize: wide)
        #expect(brightness(try await frame(filled, at: 1), 20, 360) > 100)
    }

    @Test func aHiddenWindowLeavesThePictureAlone() async throws {
        let ids = try await save(1)
        let project = try project(ids)
        let shown = try await frame(try await MovieComposer.compose(MoviePlan(project, store: store), renderSize: portrait), at: 1)
        project.orderedClips[0].selfiePlacement = .topLeft
        let moved = try await frame(try await MovieComposer.compose(MoviePlan(project, store: store), renderSize: portrait), at: 1)
        project.orderedClips[0].selfiePlacement = .hidden
        let hidden = try await frame(try await MovieComposer.compose(MoviePlan(project, store: store), renderSize: portrait), at: 1)
        // The top-left corner area: the window's cream frame and mint selfie only once it's moved there.
        let spot = (x: 110, y: 160)
        let mint = pixel(moved, spot.x, spot.y)
        #expect(mint.g > mint.r, "the selfie window is top left: \(mint)")
        #expect(pixel(hidden, spot.x, spot.y) == pixel(shown, spot.x, spot.y), "recorded top right: nothing top left")
        let warm = pixel(hidden, spot.x, spot.y)
        #expect(warm.r > warm.g)
    }

    @Test func aVoiceNotePlaysWithItsClipAndTheMovieExports() async throws {
        let ids = try await save(2)
        let project = try project(ids)
        let file = try store.store(copyOf: Fixture.voiceNote.url, in: .originals, fileExtension: "m4a")
        try #require(project.orderedClips[0].moment).voiceNotes.append(MomentVoiceNote(relativePath: file.relativePath, duration: 2, recordedAt: now))
        let composed = try await MovieComposer.compose(MoviePlan(project, store: store), renderSize: portrait)
        let voice = try #require(composed.asset.tracks(withMediaType: .audio).first)
        let segment = try #require(voice.segments.first { !$0.isEmpty })
        #expect(segment.timeMapping.target.start == .zero)
        #expect(abs(segment.timeMapping.target.duration.seconds - 2) < 0.05)

        let url = FileManager.default.temporaryDirectory.appending(path: "movie-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: url) }
        let session = try #require(AVAssetExportSession(asset: composed.asset, presetName: AVAssetExportPresetHighestQuality))
        session.videoComposition = composed.videoComposition
        session.audioMix = composed.audioMix
        try await session.export(to: url, as: .mp4)
        let movie = AVURLAsset(url: url)
        #expect(abs(try await movie.load(.duration).seconds - 5) < 0.1)
        let track = try #require(try await movie.loadTracks(withMediaType: .video).first)
        #expect(try await track.load(.naturalSize) == portrait)
        #expect(try await movie.loadTracks(withMediaType: .audio).count == 1)
    }
}
