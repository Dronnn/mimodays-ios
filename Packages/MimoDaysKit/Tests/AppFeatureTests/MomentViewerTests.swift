@testable import AppFeature
@testable import Core
@preconcurrency import AVFoundation
import DesignSystem
import Foundation
import Persistence
import SwiftData
import Testing
import TestSupport

/// The moment viewer (M05, M06): what it reads, favourites, voice notes and composed video.
@MainActor
struct MomentViewerTests {
    private let container = try! MimoDaysStore.makeContainer(inMemory: true)
    private let root = FileManager.default.temporaryDirectory.appending(path: "Viewer-\(UUID().uuidString)")
    private let store: MediaStore
    private let clock = TestDateProvider()
    private let window = SelfieWindowFrame(frame: CGRect(x: 266.7, y: 111.1, width: 112, height: 150), preview: CGSize(width: 402, height: 536))

    init() throws {
        store = try MediaStore(root: root)
    }

    private var library: MediaLibrary { MediaLibrary(context: container.mainContext, store: store, thumbnails: ThumbnailPipeline()) }

    private func save(
        video: Bool = false, multiCam: Bool = true,
        caption: String = "", note: String = "", voice: Bool = false, place: String? = nil
    ) async throws -> UUID {
        let engine = SimulatedCaptureEngine(multiCam: multiCam)
        _ = await engine.start()
        let media: CaptureResult.Media = video
            ? .video(try await engine.record(limit: .seconds(1)))
            : .photo(try await engine.capturePhoto(flash: false, silent: true))
        let capture = CaptureResult(media: media, window: .init(), capturedAt: CaptureTime(instant: Date(timeIntervalSince1970: 1_794_400_000), timeZone: .gmt))
        var draft = MomentDraft(
            capture: capture, caption: caption, window: window, promptID: nil,
            place: place.map { ReviewPlace(label: $0, latitude: 40.18, longitude: 44.51, precision: .city, source: .gps) }
        )
        draft.note = note
        if voice {
            let url = root.appending(path: "voice-\(UUID().uuidString).m4a")
            try SimulatedVoiceRecorder.writeTone(to: url, seconds: 1.2)
            draft.voice = ReviewVoiceNote(url: url, duration: 1.2, recordedAt: .now, transcript: nil)
        }
        let saver = MomentSaver(context: container.mainContext, store: store, clock: clock, freeBytes: { nil })
        return try await saver.save(draft).id
    }

    @Test func aPhotoShowsItsPicturesWordsPlaceAndVoice() async throws {
        let id = try await save(caption: "First snow", note: "It melted by noon.", voice: true, place: "Yerevan")
        let viewer = MomentViewerModel(pager: MomentPager(ids: [id], start: id), library: library)
        await viewer.load(id)
        let moment = try #require(viewer.moments[id])
        #expect(moment.title == "First snow" && moment.note == "It melted by noon." && moment.place == "Yerevan")
        #expect(viewer.image(moment.mainPath) != nil && viewer.image(moment.selfiePath) != nil)
        #expect(viewer.url(moment.composedPath) != nil)
        #expect(abs((moment.voice?.duration ?? 0) - 1.2) < 0.01)
        #expect(viewer.voiceLevels[id]?.count == MomentViewerModel.voiceBars)
        #expect(viewer.currentMoment == moment)
    }

    @Test func aFavoriteIsSavedAtOnce() async throws {
        let id = try await save()
        let viewer = MomentViewerModel(pager: MomentPager(ids: [id], start: id), library: library)
        await viewer.load(id)
        viewer.toggleFavorite(id)
        #expect(viewer.moments[id]?.isFavorite == true)
        let stored = try container.mainContext.fetch(FetchDescriptor<Moment>()).first
        #expect(stored?.isFavorite == true && container.mainContext.hasChanges == false)
        viewer.toggleFavorite(id)
        #expect(viewer.moments[id]?.isFavorite == false)
    }

    @Test func oneVoiceNotePlaysAtATime() async throws {
        let first = try await save(voice: true)
        let second = try await save(voice: true)
        let viewer = MomentViewerModel(pager: MomentPager(ids: [first, second], start: first), library: library)
        await viewer.load(first)
        await viewer.load(second)
        viewer.toggleVoice(first)
        #expect(viewer.playingVoice == first)
        viewer.toggleVoice(second)
        #expect(viewer.playingVoice == second)
        viewer.toggleVoice(second)
        #expect(viewer.playingVoice == nil)
    }

    @Test func aVideoPlaysComposedFromItsStreams() async throws {
        let id = try await save(video: true)
        let viewer = MomentViewerModel(pager: MomentPager(ids: [id], start: id), library: library)
        await viewer.load(id)
        let source = try #require(viewer.moments[id]?.video)
        #expect(source.selfiePath != nil && source.timing.window != nil && source.timing.duration > 0.5)
        let composed = try #require(await viewer.composedVideo(id))
        #expect(composed.videoComposition != nil)
    }

    /// 9.24: the player gets the two streams separately - the main one, and the selfie one for the window.
    @Test func thePlayerGetsBothStreamsApart() async throws {
        let id = try await save(video: true)
        let viewer = MomentViewerModel(pager: MomentPager(ids: [id], start: id), library: library)
        await viewer.load(id)
        let items = try #require(await viewer.playerItems(id))
        let selfie = try #require(items.selfie)
        #expect(try await items.main.asset.loadTracks(withMediaType: .video).count == 1)
        #expect(try await selfie.asset.loadTracks(withMediaType: .video).count == 1)
        #expect(try await selfie.asset.loadTracks(withMediaType: .audio).isEmpty)
    }

    /// 9.24: the two streams play together, and stop and seek together.
    @Test func bothStreamsPlayInStep() async throws {
        let id = try await save(video: true)
        let viewer = MomentViewerModel(pager: MomentPager(ids: [id], start: id), library: library)
        await viewer.load(id)
        let items = try #require(await viewer.playerItems(id))
        let player = ViewerVideoPlayer(duration: 1)
        await player.load(main: items.main, selfie: items.selfie)
        #expect(player.isReady && player.hasSelfie, "main \(items.main.status.rawValue) \(String(describing: items.main.error)), selfie \(String(describing: items.selfie?.status.rawValue)) \(String(describing: items.selfie?.error))")
        player.play()
        try await Task.sleep(for: .milliseconds(400))
        #expect(player.isPlaying)
        #expect(player.main.rate == 1 && player.selfie.rate == 1)
        let drift = abs(player.main.currentTime().seconds - player.selfie.currentTime().seconds)
        #expect(drift < 0.05, "drift \(drift)")
        #expect(player.main.currentTime().seconds > 0.2)
        player.pause()
        player.seek(to: 0.1)
        try await Task.sleep(for: .milliseconds(200))
        #expect(abs(player.selfie.currentTime().seconds - 0.1) < 0.02)
        player.stop()
    }

    /// 9.25: where the player puts the window is kept on the moment and is what the shared file shows - the
    /// selfie inside the window, the cream border around it, at the new corner and size.
    @Test func theSharedVideoHasTheWindowWhereThePlayerPutIt() async throws {
        let id = try await save(video: true)
        let viewer = MomentViewerModel(pager: MomentPager(ids: [id], start: id), library: library)
        await viewer.load(id)
        let source = try #require(viewer.moments[id]?.video)
        let layout = SelfieWindowLayout.media(width: 402, aspectRatio: source.aspectRatio, topInset: 62)
        let moved = CameraSettings.SelfieWindow(corner: .bottomLeft, scale: .large)
        viewer.setWindow(PiPLayout(layout.windowFrame(moved), source: .frontSource), for: id)

        let reread = MomentViewerModel(pager: MomentPager(ids: [id], start: id), library: library)
        await reread.load(id)
        let saved = try #require(reread.moments[id]?.video)
        #expect(saved.layout.map(layout.placement(nearest:)) == moved)

        let url = try #require(await viewer.exportVideo(id))
        defer { try? FileManager.default.removeItem(at: url) }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let frame = try await generator.image(at: CMTime(seconds: 0.5, preferredTimescale: 600)).image
        #expect(CGSize(width: frame.width, height: frame.height) == source.pixelSize)

        let window = try #require(saved.timing.window)
        let rect = PhotoComposer.placement(of: window, in: source.pixelSize).rect
        #expect(rect.midX < source.pixelSize.width / 2 && rect.midY > source.pixelSize.height / 2)
        let pixel = try Self.pixels(frame)
        // Along the window's tilted vertical axis: the border's middle, and well inside the opening.
        let border = SelfieWindowStyle.border * rect.width / SelfieWindowStyle.size.width
        let tilt = SelfieWindowStyle.tilt.radians
        func point(_ y: CGFloat) -> (Int, Int) {
            (Int((rect.midX - y * sin(tilt)).rounded()), Int((rect.midY + y * cos(tilt)).rounded()))
        }
        let edge = pixel(point(-rect.height / 2 + border / 2))
        let inside = pixel(point(-rect.height / 2 + border * 4))
        let outside = pixel(point(-rect.height / 2 - border * 3))
        #expect(edge.luma > 220, "cream border: \(edge)")
        #expect(inside.g > inside.r, "mint selfie: \(inside)")
        #expect(outside.r > outside.g, "warm main stream: \(outside)")
    }

    /// 9.25: grids show the window where the player put it - the thumbnail is composed again and replaces
    /// the old file.
    @Test func movingTheWindowRecomposesTheThumbnail() async throws {
        let id = try await save(video: true)
        let viewer = MomentViewerModel(pager: MomentPager(ids: [id], start: id), library: library)
        await viewer.load(id)
        let source = try #require(viewer.moments[id]?.video)
        func thumbnail() throws -> String {
            try #require(try container.mainContext.fetch(FetchDescriptor<Moment>()).first?.media.first { $0.role == .thumbnail }?.relativePath)
        }
        let before = try thumbnail()
        let layout = SelfieWindowLayout.media(width: 402, aspectRatio: source.aspectRatio, topInset: 62)
        viewer.setWindow(PiPLayout(layout.windowFrame(.init(corner: .bottomLeft, scale: .large)), source: .frontSource), for: id)
        await viewer.thumbnailRefresh?.value

        let after = try thumbnail()
        #expect(after != before)
        #expect(!FileManager.default.fileExists(atPath: try store.url(for: before).path))
        let image = try #require(await ImageDecoding.thumbnail(try store.url(for: after), maxPixelSize: nil))
        let window = try #require(viewer.moments[id]?.video?.timing.window)
        let rect = PhotoComposer.placement(of: window, in: CGSize(width: image.width, height: image.height)).rect
        let inside = try Self.pixels(image)((Int(rect.midX), Int(rect.midY)))
        #expect(rect.midX < CGFloat(image.width) / 2 && rect.midY > CGFloat(image.height) / 2)
        #expect(inside.g > inside.r, "mint selfie: \(inside)")
    }

    /// 9.28: a photo's window moves like a video's - kept on the moment, and the shared picture and the
    /// thumbnail are composed again with it; the old files go.
    @Test func movingAPhotosWindowRecomposesWhatIsShared() async throws {
        let id = try await save()
        let viewer = MomentViewerModel(pager: MomentPager(ids: [id], start: id), library: library)
        await viewer.load(id)
        let photo = try #require(viewer.moments[id]?.photo)
        #expect(photo.layout != nil && photo.pixelSize.width > 0)
        let before = try #require(viewer.moments[id]?.composedPath)
        let layout = SelfieWindowLayout.media(width: 402, aspectRatio: photo.aspectRatio, topInset: 62)
        let moved = CameraSettings.SelfieWindow(corner: .bottomLeft, scale: .large)
        viewer.setWindow(PiPLayout(layout.windowFrame(moved), source: .frontSource), for: id)
        await viewer.thumbnailRefresh?.value

        let composed = try #require(viewer.moments[id]?.composedPath)
        let oldFile = try store.url(for: before)
        #expect(composed != before && !FileManager.default.fileExists(atPath: oldFile.path))
        let reread = MomentViewerModel(pager: MomentPager(ids: [id], start: id), library: library)
        await reread.load(id)
        let saved = try #require(reread.moments[id]?.photo?.layout)
        #expect(layout.placement(nearest: saved) == moved && reread.moments[id]?.composedPath == composed)

        let image = try #require(await ImageDecoding.thumbnail(try store.url(for: composed), maxPixelSize: nil))
        #expect(CGSize(width: image.width, height: image.height) == photo.pixelSize)
        let rect = PhotoComposer.placement(of: saved.windowFrame(in: photo.pixelSize), in: photo.pixelSize).rect
        #expect(rect.midX < photo.pixelSize.width / 2 && rect.midY > photo.pixelSize.height / 2)
        let inside = try Self.pixels(image)((Int(rect.midX), Int(rect.midY)))
        #expect(inside.g > inside.r, "mint selfie: \(inside)")
    }

    private static func pixels(_ image: CGImage) throws -> ((Int, Int)) -> (r: Int, g: Int, b: Int, luma: Double) {
        let width = image.width, height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let context = try #require(CGContext(
            data: &data, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let bytes = data
        return { point in
            let i = (point.1 * width + point.0) * 4
            let (r, g, b) = (Int(bytes[i]), Int(bytes[i + 1]), Int(bytes[i + 2]))
            return (r, g, b, 0.299 * Double(r) + 0.587 * Double(g) + 0.114 * Double(b))
        }
    }

    /// 9.27: a single-camera video plays, shares and has no window anywhere.
    @Test func aSingleCameraVideoHasNoWindow() async throws {
        let id = try await save(video: true, multiCam: false)
        let viewer = MomentViewerModel(pager: MomentPager(ids: [id], start: id), library: library)
        await viewer.load(id)
        let source = try #require(viewer.moments[id]?.video)
        #expect(source.selfiePath == nil && source.layout == nil && source.timing.window == nil)
        let items = try #require(await viewer.playerItems(id))
        #expect(items.selfie == nil)
        let player = ViewerVideoPlayer(duration: 1)
        await player.load(main: items.main, selfie: items.selfie)
        #expect(player.isReady && !player.hasSelfie)
        player.play()
        try await Task.sleep(for: .milliseconds(300))
        #expect(player.isPlaying && player.main.currentTime().seconds > 0.1)
        player.stop()
        let url = try #require(await viewer.exportVideo(id))
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(try await AVURLAsset(url: url).loadTracks(withMediaType: .video).count == 1)
    }

    @Test func aDeletedMomentIsNotShown() async throws {
        let id = try await save()
        try container.mainContext.fetch(FetchDescriptor<Moment>()).first?.deletedAt = .now
        let viewer = MomentViewerModel(pager: MomentPager(ids: [id], start: id), library: library)
        await viewer.load(id)
        #expect(viewer.moments[id] == nil)
    }
}
