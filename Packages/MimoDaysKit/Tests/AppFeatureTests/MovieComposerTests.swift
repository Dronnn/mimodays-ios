@preconcurrency import AVFoundation
@testable import AppFeature
@testable import Core
import CoreImage
import Foundation
import Persistence
import SwiftData
import Testing
import TestSupport

/// 11.7 A project plays as one movie: clips back to back, the picture fitted to the movie's shape, the selfie window
/// on the movie's frame, captions, fades, clip sound and voice notes.
@MainActor
struct MovieComposerTests {
    private let container = try! TestStore.container()
    private let store: MediaStore
    private let now = Date(timeIntervalSince1970: 1_794_398_400) // Nov 11, 2026, noon UTC

    init() throws {
        store = try MediaStore(root: FileManager.default.temporaryDirectory.appending(path: "MovieComposer-\(UUID().uuidString)"))
    }

    private var context: ModelContext { container.mainContext }
    private var movies: MovieStore { MovieStore(context: context, store: store, now: { [now] in now }) }
    private let portrait = MovieAspectRatio.portrait9x16.renderSize(.p720)

    /// Simulated-camera moments, both cameras; `videos` indexes are 1 s videos.
    private func save(_ count: Int, videos: Set<Int> = [], format: CaptureFormat = .portrait) async throws -> [UUID] {
        let engine = SimulatedCaptureEngine()
        _ = await engine.start()
        // 16:9 is recorded with the phone sideways.
        if format == .landscape { await engine.setCaptureHold(.landscapeLeft) }
        let saver = MomentSaver(context: context, store: store, clock: TestDateProvider(), freeBytes: { nil })
        var ids: [UUID] = []
        for index in 0..<count {
            let media: CaptureResult.Media = videos.contains(index)
                ? .video(try await engine.record(limit: .seconds(1)))
                : .photo(try await engine.capturePhoto(flash: .off, silent: true))
            var capture = CaptureResult(media: media, window: .init(), capturedAt: CaptureTime(instant: now, timeZone: .gmt))
            capture.format = format
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
        try #require(project.orderedClips.count == 3)
        project.showsPlaces = false
        project.orderedClips[2].clipAudio = .muted
        let plan = MoviePlan(project, store: store)
        try #require(plan.clips.map(\.momentID) == ids)
        #expect(plan.clips[0].duration == MovieSelection.photoSeconds)
        #expect(plan.clips[1].duration > 0.9 && plan.clips[1].duration < 1.2, "the 1 s video at 10 fps: \(plan.clips[1].duration)")
        #expect(plan.clips[0].caption == "Wed, Nov 11")
        #expect(plan.title == "Test")
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

    @Test func theTitleIsOnTheFirstClipAndTheLevelsAndMusicFollowF09() async throws {
        let ids = try await save(2)
        let project = try project(ids)
        project.voiceNoteLevel = 0.5
        let voiceFile = try store.store(copyOf: Fixture.voiceNote.url, in: .originals, fileExtension: "m4a")
        try #require(project.orderedClips[1].moment).voiceNotes.append(MomentVoiceNote(relativePath: voiceFile.relativePath, duration: 2, recordedAt: now))
        project.orderedClips[1].includesVoiceNote = true
        let song = try store.store(copyOf: Fixture.voiceNote.url, in: .originals, fileExtension: "m4a")
        project.audioTracks.append(MovieAudioTrack(kind: .soundtrack, relativePath: song.relativePath, gain: 0.8))
        let composed = try await MovieComposer.compose(MoviePlan(project, store: store), renderSize: portrait)
        let instructions = composed.videoComposition.instructions.compactMap { $0 as? MovieClipInstruction }
        #expect(instructions.map(\.title) == ["Test", nil])

        let parameters = composed.audioMix.inputParameters
        #expect(parameters.count == 2, "voice notes and music")
        var start: Float = -1
        var end: Float = -1
        var range = CMTimeRange.zero
        let voice = try #require(parameters.first { $0.trackID == composed.asset.tracks(withMediaType: .audio).first?.trackID })
        #expect(voice.getVolumeRamp(for: .zero, startVolume: &start, endVolume: &end, timeRange: &range) && start == 0.5)
        let music = try #require(parameters.last)
        #expect(music.getVolumeRamp(for: .zero, startVolume: &start, endVolume: &end, timeRange: &range))
        #expect(start == 0 && end == 0.8, "fades in")
        #expect(music.getVolumeRamp(for: CMTime(seconds: 1.9, preferredTimescale: 600), startVolume: &start, endVolume: &end, timeRange: &range))
        #expect(start == 0.8 && end == 0 && abs(range.end.seconds - 2) < 0.05, "fades out where the 2 s song ends")

        project.showsTitle = false
        let untitled = try await MovieComposer.compose(MoviePlan(project, store: store), renderSize: portrait)
        let titles = untitled.videoComposition.instructions.compactMap { ($0 as? MovieClipInstruction)?.title }
        #expect(titles.isEmpty)
    }

    /// F09: the person's voice over the movie plays from the start at its level, without music's fades.
    @Test func theVoiceOverTheMoviePlaysAtItsLevelWithoutFades() async throws {
        let ids = try await save(2)
        let project = try project(ids)
        let voice = try store.store(copyOf: Fixture.voiceNote.url, in: .originals, fileExtension: "m4a")
        project.audioTracks.append(MovieAudioTrack(kind: .voiceover, relativePath: voice.relativePath, gain: 0.6))
        let plan = MoviePlan(project, store: store)
        #expect(plan.music == MoviePlan.Music(url: try store.url(for: voice.relativePath), gain: 0.6, fades: false))
        let composed = try await MovieComposer.compose(plan, renderSize: portrait)
        let track = try #require(composed.asset.tracks(withMediaType: .audio).first)
        #expect(composed.asset.tracks(withMediaType: .audio).count == 1, "photos only: the voice is the sound")
        #expect(track.segments.first { !$0.isEmpty }?.timeMapping.target.start == .zero)
        let parameters = try #require(composed.audioMix.inputParameters.first { $0.trackID == track.trackID })
        var start: Float = -1
        var end: Float = -1
        var range = CMTimeRange.zero
        for seconds in [0, 1.9] {
            #expect(parameters.getVolumeRamp(for: CMTime(seconds: seconds, preferredTimescale: 600), startVolume: &start, endVolume: &end, timeRange: &range))
            #expect(start == 0.6 && end == 0.6, "no fade at \(seconds) s")
        }
    }

    /// The 2 s fixture clip with the 2 s voice fixture as its own sound, like a video recorded with the microphone.
    private func clipWithSound() async throws -> URL {
        let composition = AVMutableComposition()
        let picture = AVURLAsset(url: Fixture.clip.url)
        let sound = AVURLAsset(url: Fixture.voiceNote.url)
        let video = try #require(try await picture.loadTracks(withMediaType: .video).first)
        let audio = try #require(try await sound.loadTracks(withMediaType: .audio).first)
        let range = try await video.load(.timeRange)
        try composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)?.insertTimeRange(range, of: video, at: .zero)
        let audioRange = CMTimeRange(start: .zero, duration: CMTimeMinimum(range.duration, try await audio.load(.timeRange).duration))
        try composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)?.insertTimeRange(audioRange, of: audio, at: .zero)
        let url = FileManager.default.temporaryDirectory.appending(path: "sound-\(UUID().uuidString).mov")
        let session = try #require(AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough))
        try await session.export(to: url, as: .mov)
        return url
    }

    /// Doc 01 §17: a clip's sound stays with its picture. Tolerance: one frame at 30 fps (33 ms), for every clip,
    /// after photos and other clips before it.
    @Test func aClipsSoundStaysWithItsPicture() async throws {
        let saver = MomentSaver(context: context, store: store, clock: TestDateProvider(), freeBytes: { nil })
        var ids: [UUID] = []
        for index in 0..<3 {
            let media: CaptureResult.Media
            if index == 1 {
                let engine = SimulatedCaptureEngine()
                _ = await engine.start()
                media = .photo(try await engine.capturePhoto(flash: .off, silent: true))
            } else {
                media = .video(CapturedVideo(mainURL: try await clipWithSound(), mainPosition: .back, selfieURL: nil, duration: 2, selfieOffset: 0, hasAudio: true))
            }
            let capture = CaptureResult(media: media, window: .init(), capturedAt: CaptureTime(instant: now.addingTimeInterval(Double(index)), timeZone: .gmt))
            ids.append(try await saver.save(MomentDraft(capture: capture, caption: "", window: nil, promptID: nil)).id)
        }
        let plan = MoviePlan(try project(ids), store: store)
        let composed = try await MovieComposer.compose(plan, renderSize: portrait)
        let frame = 1.0 / 30
        // The sound as a clip carries it (AAC in a .mov runs a little short of the voice file's 2 s).
        let probe = try await clipWithSound()
        defer { try? FileManager.default.removeItem(at: probe) }
        let soundTrack = try #require(try await AVURLAsset(url: probe).loadTracks(withMediaType: .audio).first)
        let soundLength = try await soundTrack.load(.timeRange).duration.seconds
        let main = try #require(composed.asset.tracks(withMediaType: .video).first)
        let sound = try #require(composed.asset.tracks(withMediaType: .audio).first)
        var start = 0.0
        var checked = 0
        for clip in plan.clips {
            defer { start += clip.duration }
            guard case .video = clip.media else { continue }
            let picture = try #require(main.segments.first { !$0.isEmpty && abs($0.timeMapping.target.start.seconds - start) < frame })
            let audio = try #require(sound.segments.first { !$0.isEmpty && abs($0.timeMapping.target.start.seconds - start) < frame })
            #expect(abs(audio.timeMapping.target.start.seconds - picture.timeMapping.target.start.seconds) < frame)
            #expect(abs(audio.timeMapping.source.start.seconds - picture.timeMapping.source.start.seconds) < frame)
            // All of the sound plays (this one is 1.9 s, its picture 2 s), and never past its picture.
            let expected = min(soundLength, picture.timeMapping.target.duration.seconds)
            #expect(abs(audio.timeMapping.target.duration.seconds - expected) < frame, "\(audio.timeMapping.target.duration.seconds) vs \(expected) (sound \(soundLength))")
            #expect(audio.timeMapping.target.end.seconds <= picture.timeMapping.target.end.seconds + frame)
            checked += 1
        }
        #expect(checked == 2)
    }

    /// Doc 01 §17: a voice note stays out of a movie until it's turned on for its clip.
    @Test func aNewClipLeavesItsVoiceNoteOut() async throws {
        let ids = try await save(1)
        let project = try project(ids)
        let file = try store.store(copyOf: Fixture.voiceNote.url, in: .originals, fileExtension: "m4a")
        try #require(project.orderedClips[0].moment).voiceNotes.append(MomentVoiceNote(relativePath: file.relativePath, duration: 2, recordedAt: now))
        #expect(MoviePlan(project, store: store).clips.allSatisfy { $0.voiceURL == nil })
    }

    @Test func aVoiceNotePlaysWithItsClipAndTheMovieExports() async throws {
        let ids = try await save(2)
        let project = try project(ids)
        let file = try store.store(copyOf: Fixture.voiceNote.url, in: .originals, fileExtension: "m4a")
        try #require(project.orderedClips[0].moment).voiceNotes.append(MomentVoiceNote(relativePath: file.relativePath, duration: 2, recordedAt: now))
        project.orderedClips[0].includesVoiceNote = true
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

    // MARK: Editor (U50-U55)

    /// A card between two photos, by its shared position.
    private func carded(_ ids: [UUID], look: TextCardLook) throws -> MovieProject {
        let project = try project(ids)
        project.orderedClips[1].position = 2
        context.insert(MovieTextCard(project: project, position: 1, text: "The long way home", look: look, duration: 3))
        return project
    }

    /// A card is drawn when the compositor first needs it, and only the two drawn last stay in memory (32 MB each at 4K).
    @Test func cardsAreDrawnWhenNeededAndOnlyTwoAreKept() async throws {
        let pool = CardRaster.Pool()
        let rasters = (0..<3).map { _ in CardRaster(pool: pool) { CIImage(color: .red) } }
        #expect(rasters.allSatisfy { !$0.isDrawn })
        for raster in rasters { #expect(raster.image != nil) }
        #expect(rasters.map(\.isDrawn) == [false, true, true])
        _ = rasters[0].image
        #expect(rasters.map(\.isDrawn) == [true, false, true])
        // A drawn card and its pool go with the movie: they don't keep each other.
        weak var gone: CardRaster?
        do {
            let raster = CardRaster(pool: CardRaster.Pool()) { CIImage(color: .red) }
            _ = raster.image
            gone = raster
        }
        #expect(gone == nil)

        let ids = try await save(2)
        let composed = try await MovieComposer.compose(MoviePlan(try carded(ids, look: .paper), store: store), renderSize: portrait)
        let card = try #require(composed.videoComposition.instructions.compactMap { $0 as? MovieClipInstruction }.first { $0.clip.isCard })
        #expect(card.card != nil)
    }

    @Test func aTextCardPlaysInItsPlaceOnPaperOrPlum() async throws {
        let ids = try await save(2)
        let paper = MoviePlan(try carded(ids, look: .paper), store: store)
        #expect(paper.clips.map(\.isCard) == [false, true, false])
        #expect(paper.clips[1].duration == 3)
        #expect(abs(paper.duration - (2 * MovieSelection.photoSeconds + 3)) < 0.01)
        let composed = try await MovieComposer.compose(paper, renderSize: portrait)
        let titles = composed.videoComposition.instructions.compactMap { $0 as? MovieClipInstruction }.map(\.title)
        #expect(titles == ["Test", nil, nil])

        // A card first: the title waits for the first clip instead of covering the card's words.
        let first = try project(try await save(1))
        context.insert(MovieTextCard(project: first, position: -1, text: "Hello", look: .plum))
        let opened = try await MovieComposer.compose(MoviePlan(first, store: store), renderSize: portrait)
        #expect(opened.videoComposition.instructions.compactMap { ($0 as? MovieClipInstruction)?.title } == ["Test"])
        #expect(opened.videoComposition.instructions.compactMap { $0 as? MovieClipInstruction }.first?.card != nil)
        let corner = pixel(try await frame(composed, at: 2.5 + 1.5), 20, 20)
        #expect(abs(corner.r - 0xF3) < 8 && abs(corner.g - 0xE8) < 8 && abs(corner.b - 0xDE) < 8, "paper: \(corner)")

        let ids2 = try await save(2)
        let plum = try await MovieComposer.compose(MoviePlan(try carded(ids2, look: .plum), store: store), renderSize: portrait)
        let dark = pixel(try await frame(plum, at: 2.5 + 1.5), 20, 20)
        #expect(abs(dark.r - 0x4B) < 8 && abs(dark.g - 0x29) < 8 && abs(dark.b - 0x38) < 8, "plum: \(dark)")
    }

    @Test func atmosphereHoldsThePictureBackThenFadesItIn() async throws {
        let ids = try await save(2)
        let project = try project(ids)
        project.orderedClips[1].transition = .atmosphere
        project.orderedClips[1].atmosphere = MovieAtmosphere(lead: 1)
        let plan = MoviePlan(project, store: store)
        #expect(plan.clips[1].lead == 1)
        #expect(plan.clips[0].lead == nil)
        let composed = try await MovieComposer.compose(plan, renderSize: portrait)
        let start = MovieSelection.photoSeconds
        let held = brightness(try await frame(composed, at: start + 0.5), 100, 1000)
        let fading = brightness(try await frame(composed, at: start + 1 + MovieComposer.atmosphereFade / 2), 100, 1000)
        let shown = brightness(try await frame(composed, at: start + 1 + MovieComposer.atmosphereFade + 0.2), 100, 1000)
        #expect(held < 20, "black while the sound leads: \(held)")
        #expect(fading > held && fading < shown, "half way in: \(fading) of \(shown)")
        #expect(shown > 150)

        // A lead never takes more than half the clip.
        project.orderedClips[1].atmosphere = MovieAtmosphere(lead: 5)
        #expect(MoviePlan(project, store: store).clips[1].lead == MovieSelection.photoSeconds / 2)
        let instruction = try #require(composed.videoComposition.instructions.compactMap { $0 as? MovieClipInstruction }.last)
        #expect(instruction.emergence(at: 0.5) == 0 && instruction.emergence(at: 3) == 1)
    }

    @Test func theCameraLayoutSwapsOrSplitsThePicture() async throws {
        let ids = try await save(1)
        let project = try project(ids)
        func shot(_ layout: ClipCameraLayout?) async throws -> CGImage {
            project.orderedClips[0].cameraLayout = layout
            return try await frame(try await MovieComposer.compose(MoviePlan(project, store: store), renderSize: portrait), at: 1)
        }
        let recorded = pixel(try await shot(nil), 100, 1000)
        #expect(recorded.r > recorded.g, "the rear photo is the picture: \(recorded)")
        for layout in [ClipCameraLayout.swapped, .selfieOnly] {
            let mint = pixel(try await shot(layout), 100, 1000)
            #expect(mint.g > mint.r, "\(layout): the selfie is the picture: \(mint)")
        }
        let split = try await shot(.sideBySide)
        let top = pixel(split, 100, 300)
        let bottom = pixel(split, 100, 1000)
        #expect(top.r > top.g && bottom.g > bottom.r, "rear on top, selfie below: \(top) \(bottom)")

        project.orderedClips[0].selfiePlacement = .hidden
        let hidden = try await shot(nil)
        project.orderedClips[0].selfiePlacement = nil
        let main = try await shot(.mainOnly)
        #expect(pixel(main, 560, 330) == pixel(hidden, 560, 330), "no window where it was recorded")
    }

    /// F.6/F.7: the editor's stage plays the same frames the export writes, on every shape and camera layout, with a
    /// text card and an Atmosphere lead in the movie.
    @Test(arguments: zip(
        [MovieAspectRatio.portrait9x16, .landscape16x9, .square1x1, .portrait9x16, .landscape16x9],
        [ClipCameraLayout.window, .swapped, .sideBySide, .selfieOnly, .mainOnly]
    ))
    func thePreviewIsTheExport(_ shape: MovieAspectRatio, _ layout: ClipCameraLayout) async throws {
        try await expectPreviewIsExport(shape, layout)
    }

    /// The test matrix's moment shapes: square and sideways wide moments, a video clip then a photo, in a movie of
    /// another shape - preview and export agree there too.
    @Test(arguments: zip(
        [CaptureFormat.square, .landscape, .landscape, .square],
        [MovieAspectRatio.portrait9x16, .portrait9x16, .landscape16x9, .square1x1]
    ))
    func thePreviewIsTheExportForEveryMomentShape(_ format: CaptureFormat, _ shape: MovieAspectRatio) async throws {
        let ids = try await save(2, videos: [0], format: format)
        let project = try project(ids, shape: shape)
        project.orderedClips[0].cameraLayout = .swapped
        let size = shape.renderSize(.p720)
        let composed = try await MovieComposer.compose(MoviePlan(project, store: store), renderSize: size)
        let end = try await composed.asset.load(.duration).seconds
        try await expectExportMatches(composed, at: [0.5, end - 0.5], "\(format) in \(shape)")
    }

    private func expectPreviewIsExport(_ shape: MovieAspectRatio, _ layout: ClipCameraLayout) async throws {
        let ids = try await save(2)
        let project = try carded(ids, look: .overClip)
        project.aspectRatio = shape
        project.orderedClips[0].cameraLayout = layout
        project.orderedClips[1].transition = .atmosphere
        let size = shape.renderSize(.p720)
        let composed = try await MovieComposer.compose(MoviePlan(project, store: store), renderSize: size)
        let card = MovieSelection.photoSeconds + 1.5
        let lead = MovieSelection.photoSeconds + 3 + 2
        try await expectExportMatches(composed, at: [1.0, card, lead], "\(shape) \(layout)")
    }

    /// Exports `composed` and compares the preview's frames with the file's at `times`.
    private func expectExportMatches(_ composed: MovieComposer.Composed, at times: [Double], _ name: String) async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "preview-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: url) }
        let session = try #require(AVAssetExportSession(asset: composed.asset, presetName: AVAssetExportPresetHighestQuality))
        session.videoComposition = composed.videoComposition
        try await session.export(to: url, as: .mp4)
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        for seconds in times {
            let preview = try await frame(composed, at: seconds)
            let exported = try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image
            #expect(exported.width == preview.width && exported.height == preview.height)
            for (x, y) in [(0.15, 0.2), (0.5, 0.5), (0.8, 0.8)] {
                let a = pixel(preview, Int(Double(preview.width) * x), Int(Double(preview.height) * y))
                let b = pixel(exported, Int(Double(exported.width) * x), Int(Double(exported.height) * y))
                #expect(abs(a.r - b.r) < 24 && abs(a.g - b.g) < 24 && abs(a.b - b.b) < 24, "\(name) at \(seconds) s (\(x), \(y)): \(a) vs \(b)")
            }
        }
    }
}
