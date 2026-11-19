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

    private func editor(_ ids: [UUID]) throws -> MovieEditorModel {
        let project = try movies.create(
            title: "October 2026", source: MovieSourceRule(kind: .selection, momentIDs: ids), length: .full,
            aspectRatio: .portrait9x16, fit: .fill, momentIDs: ids
        )
        return MovieEditorModel(project: project, library: library, clock: clock)
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

    @Test func musicIsCopiedInAndItsFileGoesWhenNothingUsesIt() async throws {
        let ids = try await save(2)
        let model = try editor(ids)
        let song = FileManager.default.temporaryDirectory.appending(path: "Sunday song.m4a")
        try Data([1, 2, 3]).write(to: song)
        model.setMusic(from: song)
        let track = try #require(model.music)
        #expect(track.name == "Sunday song")
        #expect(store.fileExists(track.relativePath))
        let path = track.relativePath
        model.removeMusic()
        #expect(model.music == nil)
        // Undo can still bring it back while the editor is open.
        #expect(store.fileExists(path))
        model.undo()
        #expect(model.music?.relativePath == path)
        model.removeMusic()
        // Closing (Export pushed over it too) keeps what Undo can bring back; nothing else points to it, so the
        // launch sweep takes it.
        model.close()
        #expect(store.fileExists(path))
        model.undo()
        #expect(model.music?.relativePath == path && store.fileExists(path))
        model.removeMusic()
        model.close()
        OrphanFiles.remove(context: context, store: store)
        #expect(!store.fileExists(path))
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
