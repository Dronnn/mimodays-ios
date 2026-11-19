@preconcurrency import AVFoundation
@testable import AppFeature
@testable import Core
import Foundation
import Persistence
import SwiftData
import Testing
import TestSupport

/// 11.8, 11.9: the editor's changes are kept as they're made, Undo steps back through them, and the movie follows.
@MainActor
struct MovieEditorModelTests {
    private let container = try! TestStore.container()
    private let store: MediaStore
    private let clock = TestDateProvider(Date(timeIntervalSince1970: 1_794_398_400))

    init() throws {
        store = try MediaStore(root: FileManager.default.temporaryDirectory.appending(path: "MovieEditor-\(UUID().uuidString)"))
    }

    private var context: ModelContext { container.mainContext }
    private var library: MediaLibrary { MediaLibrary(context: context, store: store, thumbnails: ThumbnailPipeline()) }
    private var movies: MovieStore { MovieStore(context: context, store: store, now: { [clock] in clock.now() }) }

    private func save(_ count: Int, videos: Set<Int> = []) async throws -> [UUID] {
        let engine = SimulatedCaptureEngine()
        _ = await engine.start()
        let saver = MomentSaver(context: context, store: store, clock: clock, freeBytes: { nil })
        var ids: [UUID] = []
        for index in 0..<count {
            let media: CaptureResult.Media = videos.contains(index)
                ? .video(try await engine.record(limit: .seconds(1)))
                : .photo(try await engine.capturePhoto(flash: .off, silent: true))
            let capture = CaptureResult(media: media, window: .init(), capturedAt: CaptureTime(instant: clock.now().addingTimeInterval(Double(index) * 3600), timeZone: .gmt))
            let draft = MomentDraft(
                capture: capture, caption: "",
                window: SelfieWindowFrame(frame: CGRect(x: 266.7, y: 111.1, width: 112, height: 150), preview: CGSize(width: 402, height: 536)),
                promptID: nil
            )
            ids.append(try await saver.save(draft).id)
        }
        return ids
    }

    private func editor(_ ids: [UUID], voice: VoiceServices = .simulated) throws -> MovieEditorModel {
        let project = try movies.create(
            title: "October 2026", source: MovieSourceRule(kind: .selection, momentIDs: ids), length: .full,
            aspectRatio: .portrait9x16, fit: .fill, momentIDs: ids
        )
        return MovieEditorModel(project: project, library: library, clock: clock, voice: voice)
    }

    private func order(_ model: MovieEditorModel) -> [UUID] { model.clips.compactMap { $0.moment?.id } }

    /// What's in the store, read fresh.
    private func stored(_ model: MovieEditorModel) throws -> [UUID] {
        let id = model.project.id
        let project = try #require(try context.fetch(FetchDescriptor<MovieProject>(predicate: #Predicate { $0.id == id })).first)
        return project.orderedClips.compactMap { $0.moment?.id }
    }

    @Test func removingAClipSavesAndUndoBringsItBack() async throws {
        let ids = try await save(5)
        let model = try editor(ids)
        model.select(2)
        model.remove()
        #expect(order(model) == [ids[0], ids[1], ids[3], ids[4]])
        #expect(try stored(model) == [ids[0], ids[1], ids[3], ids[4]])
        #expect(model.plan.clips.count == 4)
        #expect(model.canUndo)
        model.undo()
        #expect(order(model) == ids)
        #expect(try stored(model) == ids)
        #expect(!model.canUndo)
    }

    @Test func theLastClipCantBeRemoved() async throws {
        let ids = try await save(1)
        let model = try editor(ids)
        #expect(!model.canRemove)
        model.remove()
        #expect(order(model) == ids)
    }

    @Test func movingAClipReordersTheMovie() async throws {
        let ids = try await save(4)
        let model = try editor(ids)
        model.move(from: 0, to: 3)
        #expect(order(model) == [ids[1], ids[2], ids[3], ids[0]])
        #expect(model.selected == 3)
        #expect(model.plan.clips.map(\.momentID) == [ids[1], ids[2], ids[3], ids[0]])
        model.undo()
        #expect(order(model) == ids)
    }

    @Test func transitionShapeAndCaptionsAreKept() async throws {
        let ids = try await save(3)
        let model = try editor(ids)
        model.select(1)
        model.setTransition(.fade)
        model.setAspectRatio(.square1x1)
        model.setFit(.showAll)
        model.setShowsDates(false)
        model.setPlacement(.hidden)
        #expect(model.clips[1].transition == .fade)
        #expect(model.plan.clips[1].transition == .fade)
        #expect(model.plan.clips[1].placement == .hidden)
        #expect(model.project.aspectRatio == .square1x1)
        #expect(model.plan.aspectRatio == .square1x1)
        #expect(model.plan.fit == .showAll)
        #expect(model.plan.clips[0].caption == nil || !(model.plan.clips[0].caption ?? "").contains("Nov"))
        for _ in 0..<5 { model.undo() }
        #expect(model.clips[1].transition == .cut)
        #expect(model.project.aspectRatio == .portrait9x16)
        #expect(model.project.fit == .fill)
        #expect(model.project.showsDates)
        #expect(model.clips[1].selfiePlacement == nil)
    }

    @Test func everyChangeMovesTheEditedDate() async throws {
        let ids = try await save(2)
        let model = try editor(ids)
        clock.advance(by: 3600)
        model.setTransition(.fade)
        #expect(model.project.updatedAt == clock.now())
    }

    @Test func trimmingAPhotoSetsHowLongItShows() async throws {
        let ids = try await save(2)
        let model = try editor(ids)
        model.select(0)
        model.trim(start: 0, end: 4)
        #expect(model.plan.clips[0].duration == 4)
        #expect(model.duration == 4 + MovieSelection.photoSeconds)
        model.trim(start: 0, end: 30)
        #expect(model.plan.clips[0].duration == MoviePlan.longestPhoto)
    }

    @Test func trimmingAVideoPlaysThatPart() async throws {
        let ids = try await save(2, videos: [1])
        let model = try editor(ids)
        model.select(1)
        model.trim(start: 0.2, end: 0.7)
        guard case let .video(start, _, _) = model.plan.clips[1].media else {
            Issue.record("Not a video")
            return
        }
        #expect(abs(start - 0.2) < 0.001)
        #expect(abs(model.plan.clips[1].duration - 0.5) < 0.001)
    }

    @Test func replaceShowsAnotherMomentInTheSamePlace() async throws {
        let ids = try await save(4)
        let model = try editor(Array(ids.prefix(3)))
        model.select(1)
        model.setTransition(.fade)
        let offered = model.replacements().map(\.id)
        #expect(offered == [ids[3]])
        model.replace(with: ids[3])
        #expect(order(model) == [ids[0], ids[3], ids[2]])
        #expect(model.clips[1].transition == .fade)
        model.undo()
        #expect(order(model) == Array(ids.prefix(3)))
    }

    @Test func titleIsTheMoviesNameAndCanBeHidden() async throws {
        let ids = try await save(2)
        let model = try editor(ids)
        model.setTitle("  Autumn  ", shows: false)
        #expect(model.project.title == "Autumn")
        #expect(model.plan.title == nil)
        model.setTitle("", shows: true)
        #expect(model.project.title == "Autumn")
        #expect(model.plan.title == "Autumn")
    }

    @Test func aSliderDragIsOneUndoStep() async throws {
        let ids = try await save(2)
        let model = try editor(ids)
        model.beginLevelChange()
        model.setClipSoundLevel(0.5)
        model.setClipSoundLevel(0.2)
        model.setClipSoundLevel(1.4)
        model.endLevelChange()
        #expect(model.project.clipSoundLevel == 1)
        #expect(model.plan.clipSoundLevel == 1)
        model.undo()
        #expect(model.project.clipSoundLevel == 0.7)
    }

    /// A song in Files: the voice fixture under a song's name.
    private func song() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString)/Sunday song.m4a")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: Fixture.voiceNote.url, to: url)
        return url
    }

    @Test func musicIsCopiedInAndItsFileGoesWhenNothingUsesIt() async throws {
        let ids = try await save(2)
        let model = try editor(ids)
        model.setMusic(from: try song())
        let track = try #require(model.track)
        #expect(track.name == "Sunday song")
        #expect(store.fileExists(track.relativePath))
        let path = track.relativePath
        model.removeTrack()
        #expect(model.track == nil)
        // Undo can still bring it back while the editor is open.
        #expect(store.fileExists(path))
        model.undo()
        #expect(model.track?.relativePath == path)
        model.removeTrack()
        // Closing (Export pushed over it too) keeps what Undo can bring back; nothing else points to it, so the
        // launch sweep takes it.
        model.close()
        #expect(store.fileExists(path))
        model.undo()
        #expect(model.track?.relativePath == path && store.fileExists(path))
        model.removeTrack()
        model.close()
        OrphanFiles.remove(context: context, store: store)
        #expect(!store.fileExists(path))
    }

    @Test func aFileThatIsntAudioLeavesTheMusicAsItWas() async throws {
        let ids = try await save(2)
        let model = try editor(ids)
        model.setMusic(from: try song())
        let kept = try #require(model.track).relativePath
        let files = Set(try store.orphans(referenced: []))
        let broken = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).mp3")
        try Data([1, 2, 3]).write(to: broken)
        model.setMusic(from: broken)
        #expect(model.track?.relativePath == kept && model.project.audioTracks.count == 1)
        #expect(Set(try store.orphans(referenced: [])) == files, "nothing copied in")
        model.undo()
        #expect(model.track == nil, "only the song was a step")
    }

    /// Export pushed over the editor right after a change closes it before the stage caught up; coming back builds
    /// the stage again, so it plays the movie as it now is.
    @Test func comingBackAfterAChangeTheStageHadntCaughtUpWithPlaysIt() async throws {
        let ids = try await save(2)
        let model = try editor(ids)
        await model.settled()
        #expect((model.player.currentItem?.asset as? AVComposition)?.tracks(withMediaType: .audio).isEmpty == true, "photos only: no sound yet")
        model.addVoiceover(at: try recordedVoice())
        model.close()
        model.observeTime()
        await model.settled()
        #expect((model.player.currentItem?.asset as? AVComposition)?.tracks(withMediaType: .audio).count == 1, "the voice")
    }

    // MARK: Voice over the movie (F09)

    /// A recorded voice, `seconds` long, where a recording would leave it.
    private func recordedVoice(seconds: TimeInterval = 2) throws -> URL {
        let url = try CaptureFiles.temporaryURL("m4a")
        try SimulatedVoiceRecorder.writeTone(to: url, seconds: seconds)
        return url
    }

    @Test func aRecordedVoiceBecomesTheMoviesTrackInPlaceOfMusic() async throws {
        let ids = try await save(2)
        let model = try editor(ids)
        model.setMusic(from: try song())
        let music = try #require(model.track).relativePath
        let recorded = try recordedVoice()
        model.addVoiceover(at: recorded)
        #expect(model.project.audioTracks.count == 1, "one track under the movie")
        let track = try #require(model.track)
        #expect(track.kind == .voiceover && track.startOffset == 0 && track.name == nil)
        #expect(track.gain == MovieEditorModel.voiceoverGain)
        #expect(track.relativePath.hasPrefix(MediaStore.Area.originals.rawValue))
        #expect(store.fileExists(track.relativePath) && !FileManager.default.fileExists(atPath: recorded.path()), "moved in")
        // The movie plays it, as it is: no fades over the first and last words.
        #expect(model.plan.music == MoviePlan.Music(url: try store.url(for: track.relativePath), gain: MovieEditorModel.voiceoverGain, fades: false))
        // Its level is the person's to set, one Undo step for the drag.
        model.beginLevelChange()
        model.setTrackLevel(0.3)
        model.endLevelChange()
        #expect(model.track?.gain == 0.3 && model.plan.music?.gain == 0.3)
        model.undo()
        #expect(model.track?.gain == MovieEditorModel.voiceoverGain)
        // Undo brings the music back; its file stayed for that.
        model.undo()
        #expect(model.track?.kind == .soundtrack && model.track?.relativePath == music && store.fileExists(music))
    }

    @Test func recordingAgainReplacesTheVoiceAndTheOldFileGoesOnceNothingUsesIt() async throws {
        let ids = try await save(2)
        let model = try editor(ids)
        model.addVoiceover(at: try recordedVoice())
        let first = try #require(model.track).relativePath
        model.addVoiceover(at: try recordedVoice(seconds: 1))
        let second = try #require(model.track).relativePath
        #expect(first != second && model.project.audioTracks.count == 1)
        // Undo can still bring the first one back while the editor is open.
        #expect(store.fileExists(first))
        model.removeTrack()
        #expect(model.track == nil && model.plan.music == nil)
        model.close()
        OrphanFiles.remove(context: context, store: store)
        #expect(!store.fileExists(first) && !store.fileExists(second))
    }

    @Test func aTooShortOrUnreadableRecordingLeavesTheTrackAsItWas() async throws {
        let ids = try await save(2)
        let model = try editor(ids)
        model.addVoiceover(at: try recordedVoice())
        let kept = try #require(model.track).relativePath
        let short = try recordedVoice(seconds: 0.2)
        model.addVoiceover(at: short)
        let broken = try CaptureFiles.temporaryURL("m4a")
        try Data([1, 2, 3]).write(to: broken)
        model.addVoiceover(at: broken)
        #expect(model.track?.relativePath == kept && model.project.audioTracks.count == 1)
        #expect(!FileManager.default.fileExists(atPath: short.path()) && !FileManager.default.fileExists(atPath: broken.path()), "dropped")
        model.undo()
        #expect(model.track == nil, "only the first recording was a step")
    }

    @Test func theMoviePlaysFromTheStartWhileTheVoiceRecordsAndItsLengthIsTheLimit() async throws {
        let ids = try await save(2, videos: [0])
        let recorderClock = TestDateProvider()
        let model = try editor(ids, voice: VoiceServices(makeRecorder: { SimulatedVoiceRecorder(now: recorderClock.now) }, transcriber: SimulatedTranscriber()))
        await model.settled()
        model.select(1)
        let recording = try #require(await model.startVoiceover())
        #expect(recording.limit == model.duration)
        #expect(model.isPlaying && model.time == 0 && model.player.isMuted, "silent, so its sound isn't recorded into the voice")
        // The microphone started with the movie on its first frame.
        #expect(model.player.currentItem?.status == .readyToPlay && model.player.currentTime().seconds < 0.1)
        #expect(await model.startVoiceover() == nil, "one take at a time")
        recorderClock.advance(by: 1.5)
        model.finishVoiceover(recording)
        #expect(!model.isPlaying && !model.player.isMuted && model.voiceover == nil)
        let track = try #require(model.track)
        #expect(track.kind == .voiceover && store.fileExists(track.relativePath))
        // The sheet going away later finishes nothing more.
        model.finishVoiceover(recording)
        model.undo()
        #expect(model.track == nil, "one take, one step")
    }

    /// The app left before the recording's sheet came up: the take ends there and the preview's sound comes back.
    @Test func aTakeFinishedBeforeItsSheetCameUpIsKept() async throws {
        let ids = try await save(2)
        let recorderClock = TestDateProvider()
        let model = try editor(ids, voice: VoiceServices(makeRecorder: { SimulatedVoiceRecorder(now: recorderClock.now) }, transcriber: SimulatedTranscriber()))
        _ = try #require(await model.startVoiceover())
        recorderClock.advance(by: 1)
        model.finishVoiceover(try #require(model.voiceover))
        #expect(model.track?.kind == .voiceover && !model.player.isMuted && !model.isPlaying)
    }

    @Test func aShortMovieKeepsAShortTake() async throws {
        let ids = try await save(1, videos: [0])
        let model = try editor(ids)
        model.trim(start: 0, end: 0.3)
        #expect(model.duration < MovieEditorModel.shortestVoiceover)
        model.addVoiceover(at: try recordedVoice(seconds: 0.4))
        #expect(model.track?.kind == .voiceover)
    }

    @Test func aMicrophoneThatCantStartRecordsNothing() async throws {
        let ids = try await save(2)
        let model = try editor(ids, voice: VoiceServices(makeRecorder: { FailingRecorder() }, transcriber: SimulatedTranscriber()))
        model.addVoiceover(at: try recordedVoice())
        let kept = try #require(model.track).relativePath
        await model.settled()
        #expect(await model.startVoiceover() == nil)
        #expect(!model.isPlaying && !model.player.isMuted && model.voiceover == nil && model.track?.relativePath == kept)
    }

    @Test func deletedMomentsDropOutOfTheMovie() async throws {
        let ids = try await save(3)
        let model = try editor(ids)
        let id = ids[1]
        let moment = try #require(try context.fetch(FetchDescriptor<Moment>(predicate: #Predicate { $0.id == id })).first)
        moment.deletedAt = clock.now()
        try context.save()
        model.reload()
        #expect(order(model) == [ids[0], ids[2]])
        #expect(model.plan.clips.count == 2)
    }

    @Test func thePlayheadFollowsTheTime() async throws {
        let ids = try await save(3)
        let model = try editor(ids)
        model.select(1)
        #expect(model.time == MovieSelection.photoSeconds)
        #expect(model.playhead?.index == 1)
        #expect(model.playhead?.fraction == 0)
        model.seek(to: MovieSelection.photoSeconds * 2.5)
        #expect(model.playhead?.index == 2)
        #expect(abs((model.playhead?.fraction ?? 0) - 0.5) < 0.001)
    }

    /// Scrubbed to the third clip in the preview, Edit lands on it: Trim or Remove act on what was last seen.
    @Test func backFromThePreviewTheClipThereIsSelected() async throws {
        let ids = try await save(3)
        let model = try editor(ids)
        await model.settled()
        #expect(model.selected == 0)
        await model.player.seek(
            to: CMTime(seconds: MovieSelection.photoSeconds * 2.5, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero
        )
        model.caughtUp()
        #expect(model.selected == 2)
    }

    @Test func theStageGetsAPlayableMovie() async throws {
        let ids = try await save(2, videos: [1])
        let model = try editor(ids)
        await model.settled()
        let item = try #require(model.player.currentItem)
        #expect(item.videoComposition != nil)
        #expect(!model.failed)
    }

    @Test func duplicateKeepsEveryEdit() async throws {
        let ids = try await save(2)
        let model = try editor(ids)
        model.setTitle("Fall", shows: false)
        model.beginLevelChange()
        model.setVoiceNoteLevel(0.3)
        model.endLevelChange()
        let copy = try movies.duplicate(model.project)
        #expect(copy.showsTitle == false)
        #expect(copy.voiceNoteLevel == 0.3)
    }

    // MARK: U50-U54

    @Test func aCardGoesInFirstMovesBetweenClipsAndUndoes() async throws {
        let ids = try await save(2)
        let model = try editor(ids)
        model.addCard()
        #expect(model.items.count == 3 && model.selectedCard != nil && model.selected == 0)
        #expect(model.plan.clips.map(\.isCard) == [true, false, false])
        model.move(from: 0, to: 1)
        #expect(model.items[1].card != nil)
        #expect(model.plan.clips.map(\.isCard) == [false, true, false])
        #expect(order(model) == ids)
        model.undo()
        #expect(model.items[0].card != nil)
        model.undo()
        #expect(model.items.count == 2 && model.project.textCards.isEmpty)
    }

    @Test func aCardsWordsLookAndLengthAreKept() async throws {
        let ids = try await save(1)
        let model = try editor(ids)
        model.addCard()
        let card = try #require(model.selectedCard)
        model.setCardText(String(repeating: "a", count: 80), of: card)
        #expect(model.selectedCard?.text.count == MovieEditorModel.cardLimit)
        model.setCardText("   ", of: card)
        #expect(model.selectedCard?.text.count == MovieEditorModel.cardLimit, "blank words are ignored")
        model.setCardLook(.plum)
        model.setCardDuration(5)
        #expect(model.plan.clips[0].duration == 5)
        guard case let .card(text, look) = model.plan.clips[0].media else { Issue.record("not a card"); return }
        #expect(text.count == MovieEditorModel.cardLimit && look == .plum)
        #expect(model.canRemove, "a card can go even with one clip")
        model.remove()
        #expect(model.items.count == 1 && model.project.textCards.isEmpty)
    }

    @Test func theTransitionDotAndAtmosphereAreKept() async throws {
        let ids = try await save(3)
        let model = try editor(ids)
        model.setTransition(.atmosphere, at: 2)
        model.setAtmosphere(MovieAtmosphere(lead: 1, leadsWith: .voiceComment), at: 2)
        #expect(model.transition(at: 2) == .atmosphere)
        #expect(model.atmosphere(at: 2) == MovieAtmosphere(lead: 1, leadsWith: .voiceComment))
        #expect(model.plan.clips[2].lead == 1)
        model.undo()
        #expect(model.atmosphere(at: 2) == MovieAtmosphere())
        model.undo()
        #expect(model.transition(at: 2) == .cut && model.plan.clips[2].lead == nil)
    }

    @Test func camerasWindowAndSoundArePerClip() async throws {
        let ids = try await save(2)
        let model = try editor(ids)
        model.select(1)
        model.setCameraLayout(.sideBySide)
        #expect(model.plan.clips[1].layout == .sideBySide && model.plan.clips[0].layout == nil)
        model.setPlacement(.topLeft)
        let frame = PiPLayout(centerX: 0.3, centerY: 0.7, scale: 0.35)
        model.setWindow(frame)
        #expect(model.clips[1].pipFrame == frame && model.clips[1].selfiePlacement == nil)
        #expect(model.plan.clips[1].window == frame)
        #expect(model.clips[1].cameraLayout == .sideBySide, "a chosen layout stays")
        model.setClipSound(false)
        #expect(!model.plan.clips[1].soundOn)
        model.beginLevelChange()
        model.setClipVolume(1.4)
        #expect(model.clips[1].clipVolume == 1)
        model.setClipVolume(0.4)
        model.endLevelChange()
        #expect(model.plan.clips[1].volume == 0.4)
        for _ in 0..<5 { model.undo() }
        #expect(model.clips[1].cameraLayout == nil && model.clips[1].pipFrame == nil && model.clips[1].clipAudio != .muted)
    }
}

/// A microphone that won't start (taken by a call, or not allowed).
@MainActor
private final class FailingRecorder: VoiceRecorder {
    func start(to _: URL, limit _: TimeInterval) throws { throw VoiceRecorderError.couldNotStart }
    var elapsed: TimeInterval { 0 }
    var level: Float { 0 }
    var isRecording: Bool { false }
    func stop() {}
}
