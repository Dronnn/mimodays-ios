@testable import AppFeature
@testable import Core
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

    private func save(video: Bool = false, caption: String = "", note: String = "", voice: Bool = false, place: String? = nil) async throws -> UUID {
        let engine = SimulatedCaptureEngine()
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

    @Test func aDeletedMomentIsNotShown() async throws {
        let id = try await save()
        try container.mainContext.fetch(FetchDescriptor<Moment>()).first?.deletedAt = .now
        let viewer = MomentViewerModel(pager: MomentPager(ids: [id], start: id), library: library)
        await viewer.load(id)
        #expect(viewer.moments[id] == nil)
    }
}
