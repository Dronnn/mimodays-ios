@testable import AppFeature
@testable import Core
import Foundation
import Persistence
import SwiftData
import Testing
import TestSupport

/// 9.5 Edit moment (M07): words, favourite, place and voice note change only on Save; files follow the store.
@MainActor
struct EditMomentTests {
    private let container = try! MimoDaysStore.makeContainer(inMemory: true)
    private let root = FileManager.default.temporaryDirectory.appending(path: "Edit-\(UUID().uuidString)")
    private let store: MediaStore

    init() throws {
        store = try MediaStore(root: root)
    }

    private var library: MediaLibrary { MediaLibrary(context: container.mainContext, store: store, thumbnails: ThumbnailPipeline()) }

    private func tone(seconds: Double) throws -> URL {
        let url = root.appending(path: "voice-\(UUID().uuidString).m4a")
        try SimulatedVoiceRecorder.writeTone(to: url, seconds: seconds)
        return url
    }

    private func save(voice: Bool = false, place: String? = "Yerevan") async throws -> UUID {
        let engine = SimulatedCaptureEngine()
        _ = await engine.start()
        let capture = CaptureResult(
            media: .photo(try await engine.capturePhoto(flash: false, silent: true)), window: .init(),
            capturedAt: CaptureTime(instant: Date(timeIntervalSince1970: 1_794_400_000), timeZone: .gmt)
        )
        var draft = MomentDraft(
            capture: capture, caption: "First snow",
            window: SelfieWindowFrame(frame: CGRect(x: 266.7, y: 111.1, width: 112, height: 150), preview: CGSize(width: 402, height: 536)),
            promptID: nil, place: place.map { ReviewPlace(label: $0, latitude: 40.18, longitude: 44.51, precision: .city, source: .gps) }
        )
        if voice {
            draft.voice = ReviewVoiceNote(url: try tone(seconds: 1.2), duration: 1.2, recordedAt: .now)
        }
        return try await MomentSaver(context: container.mainContext, store: store, clock: TestDateProvider(), freeBytes: { nil }).save(draft).id
    }

    private func edit(_ id: UUID) throws -> EditMomentModel {
        try #require(EditMomentModel(id: id, library: library, voice: .simulated, places: .simulated))
    }

    private func moment() throws -> Moment {
        try #require(try container.mainContext.fetch(FetchDescriptor<Moment>()).first)
    }

    @Test func wordsAndFavoriteAreSavedTrimmed() async throws {
        let edit = try edit(try await save())
        #expect(edit.caption == "First snow" && edit.place?.label == "Yerevan" && edit.voice == nil && !edit.hasChanges)
        edit.caption = "  First snow, finally "
        edit.note = "\nIt melted by noon.\n"
        edit.isFavorite = true
        #expect(edit.hasChanges)
        #expect(try moment().title == "First snow")
        try await edit.save()
        let saved = try moment()
        #expect(saved.title == "First snow, finally" && saved.note == "It melted by noon." && saved.isFavorite)
        #expect(container.mainContext.hasChanges == false)
    }

    @Test func emptyWordsClearTheCaptionAndNote() async throws {
        let edit = try edit(try await save())
        edit.caption = "  "
        try await edit.save()
        #expect(try moment().title == nil && moment().note == nil)
    }

    @Test func aPlaceCanBeChangedOrRemoved() async throws {
        let edit = try edit(try await save())
        edit.choose(ReviewPlace(label: "Dilijan", latitude: 40.74, longitude: 44.86, precision: .exact, source: .manual))
        try await edit.save()
        #expect(try moment().location?.placeLabel == "Dilijan" && moment().location?.source == .manual)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<MomentLocation>()) == 1)

        let again = try self.edit(try moment().id)
        again.choose(nil)
        #expect(again.hasChanges)
        try await again.save()
        #expect(try moment().location == nil)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<MomentLocation>()) == 0)
    }

    @Test func aNewRecordingReplacesTheVoiceNoteAndItsFile() async throws {
        let edit = try edit(try await save(voice: true))
        let oldPath = try #require(try moment().voiceNotes.first?.relativePath)
        #expect(edit.voice?.duration == 1.2)
        let recording = try tone(seconds: 2)
        edit.addVoice(at: recording, recordedAt: .now)
        #expect(abs((edit.voice?.duration ?? 0) - 2) < 0.1 && edit.hasChanges)
        try await edit.save()
        let note = try #require(try moment().voiceNotes.first)
        #expect(try moment().voiceNotes.count == 1 && note.relativePath != oldPath && abs(note.duration - 2) < 0.1)
        #expect(store.fileExists(note.relativePath) && !store.fileExists(oldPath))
        #expect(!FileManager.default.fileExists(atPath: recording.path()))
        #expect(try container.mainContext.fetchCount(FetchDescriptor<MomentVoiceNote>()) == 1)
    }

    /// 9.14: the voice note plays from its row - the saved one, and a new recording before Save; recording
    /// again or removing it stops it.
    @Test func theVoiceNotePlaysFromItsRow() async throws {
        let edit = try edit(try await save(voice: true))
        edit.toggleVoice()
        try await Task.sleep(for: .milliseconds(400))
        #expect(edit.isPlayingVoice && edit.voiceTime > 0.1, "time \(edit.voiceTime)")
        edit.toggleVoice()
        #expect(!edit.isPlayingVoice && edit.voiceTime == 0)

        edit.toggleVoice()
        edit.addVoice(at: try tone(seconds: 2), recordedAt: .now)
        #expect(!edit.isPlayingVoice)
        edit.toggleVoice()
        try await Task.sleep(for: .milliseconds(400))
        #expect(edit.isPlayingVoice && edit.voiceTime > 0.1)
        edit.removeVoice()
        #expect(!edit.isPlayingVoice)
        edit.toggleVoice()
        #expect(!edit.isPlayingVoice)
    }

    @Test func aRemovedVoiceNoteLeavesNoFile() async throws {
        let edit = try edit(try await save(voice: true))
        let oldPath = try #require(try moment().voiceNotes.first?.relativePath)
        edit.removeVoice()
        try await edit.save()
        #expect(try moment().voiceNotes.isEmpty && !store.fileExists(oldPath))
    }

    @Test func cancellingDropsANewRecording() async throws {
        let edit = try edit(try await save(voice: true))
        let recording = try tone(seconds: 1)
        edit.addVoice(at: recording, recordedAt: .now)
        edit.discardRecording()
        #expect(!FileManager.default.fileExists(atPath: recording.path()) && !edit.hasChanges)
        #expect(try moment().voiceNotes.count == 1)
    }

    @Test func aTooShortRecordingIsDropped() async throws {
        let edit = try edit(try await save())
        let recording = try tone(seconds: 0.2)
        edit.addVoice(at: recording, recordedAt: .now)
        #expect(edit.voice == nil && !FileManager.default.fileExists(atPath: recording.path()))
    }

    @Test func aDeletedMomentCantBeEdited() async throws {
        let id = try await save()
        try moment().deletedAt = .now
        #expect(EditMomentModel(id: id, library: library, voice: .simulated, places: .simulated) == nil)
    }
}
