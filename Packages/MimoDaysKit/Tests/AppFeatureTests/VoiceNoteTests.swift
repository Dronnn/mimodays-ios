@testable import AppFeature
@testable import Core
import Foundation
import Persistence
import SwiftData
import Testing
import TestSupport

/// 7.3: the voice note (C09/C10), recorded on the simulated recorder, kept with the draft, saved on its own.
@MainActor
struct VoiceNoteTests {
    private final class Clock {
        var now = Date(timeIntervalSince1970: 1_000)
    }

    private let clock = Clock()
    private let drafts = ReviewDraftStore(root: FileManager.default.temporaryDirectory.appending(path: "VoiceNoteTests-\(UUID().uuidString)"))
    private let time = CaptureTime(instant: Date(timeIntervalSince1970: 1_000), timeZone: .gmt)

    private var services: VoiceServices {
        let clock = clock
        return VoiceServices(makeRecorder: { SimulatedVoiceRecorder(now: { clock.now }) }, transcriber: SimulatedTranscriber(text: "Look, the first snow"))
    }

    private func review(drafts: ReviewDraftStore? = nil) async throws -> ReviewModel {
        let engine = SimulatedCaptureEngine()
        _ = await engine.start()
        let capture = CaptureResult(media: .photo(try await engine.capturePhoto(flash: false, silent: true)), window: .init(), capturedAt: time)
        return ReviewModel(capture: try drafts?.adopt(capture) ?? capture, drafts: drafts, voice: services)
    }

    /// Records `seconds` on the simulated clock and hands the file to review, as closing C09 does.
    private func record(_ seconds: TimeInterval, into review: ReviewModel) throws -> VoiceRecording {
        let recording = try review.makeVoiceRecording()
        #expect(recording.start())
        clock.now += seconds
        recording.tick()
        recording.finish()
        review.addVoice(at: recording.url, recordedAt: recording.startedAt)
        return recording
    }

    @Test func aRecordingBecomesTheVoiceNoteWithItsWaveformAndWords() async throws {
        let review = try await review()
        defer { review.discard() }
        #expect(!review.hasAnnotations)
        let recording = try record(12, into: review)
        #expect(recording.levels.count == 11)
        let voice = try #require(review.voice)
        #expect(abs(voice.duration - 12) < 0.2)
        #expect(review.voiceLevels.count == ReviewModel.voiceBars && review.voiceLevels.max() == 1)
        #expect(review.hasAnnotations)
        await review.finishTranscription()
        #expect(review.voice?.transcript == "Look, the first snow")
    }

    @Test func recordingStopsByItselfAtOneMinute() async throws {
        let review = try await review()
        defer { review.discard() }
        let recording = try review.makeVoiceRecording()
        #expect(recording.start())
        clock.now += 75
        recording.tick()
        #expect(recording.isFinished)
        #expect(recording.elapsed == ReviewModel.voiceLimit)
        #expect(recording.levels.count == VoiceRecording.bars)
        try? FileManager.default.removeItem(at: recording.url)
    }

    @Test func aTapThatRecordsAlmostNothingAddsNothing() async throws {
        let review = try await review()
        defer { review.discard() }
        let recording = try review.makeVoiceRecording()
        #expect(recording.start())
        try SimulatedVoiceRecorder.writeTone(to: recording.url, seconds: 0.2)
        review.addVoice(at: recording.url, recordedAt: clock.now)
        #expect(review.voice == nil)
        #expect(!FileManager.default.fileExists(atPath: recording.url.path))
    }

    @Test func recordingAgainReplacesItAndRemovingDeletesTheFile() async throws {
        let review = try await review()
        defer { review.discard() }
        let first = try record(3, into: review)
        let second = try record(5, into: review)
        #expect(!FileManager.default.fileExists(atPath: first.url.path))
        #expect(review.voice?.url == second.url)
        review.removeVoice()
        #expect(review.voice == nil && review.voiceLevels.isEmpty && !review.hasAnnotations)
        #expect(!FileManager.default.fileExists(atPath: second.url.path))
    }

    @Test func theVoiceNoteComesBackAfterARelaunchAndRetakeDropsIt() async throws {
        defer { drafts.clear() }
        let review = try await review(drafts: drafts)
        let recording = try record(4, into: review)
        await review.finishTranscription()
        #expect(recording.url.deletingLastPathComponent().standardizedFileURL == drafts.root.standardizedFileURL)

        let draft = try #require(drafts.load())
        let restored = ReviewModel(draft: draft, drafts: drafts, voice: services)
        #expect(restored.voice == review.voice)
        #expect(restored.voice?.transcript == "Look, the first snow")
        #expect(restored.voiceLevels.count == ReviewModel.voiceBars)

        restored.discard()
        #expect(drafts.load() == nil)
        #expect(!FileManager.default.fileExists(atPath: recording.url.path))
    }

    @Test func aMissingVoiceFileIsDroppedFromTheDraft() async throws {
        defer { drafts.clear() }
        let review = try await review(drafts: drafts)
        let recording = try record(4, into: review)
        try FileManager.default.removeItem(at: recording.url)
        let draft = try #require(drafts.load())
        #expect(draft.voice == nil)
    }

    @Test func theTranscriptIsLeftOutWhenNoWordsCameBack() async throws {
        let quiet = VoiceServices(makeRecorder: { [clock] in SimulatedVoiceRecorder(now: { clock.now }) }, transcriber: SimulatedTranscriber(text: nil))
        let engine = SimulatedCaptureEngine()
        _ = await engine.start()
        let review = ReviewModel(
            capture: CaptureResult(media: .photo(try await engine.capturePhoto(flash: false, silent: true)), window: .init(), capturedAt: time),
            voice: quiet
        )
        defer { review.discard() }
        _ = try record(2, into: review)
        await review.finishTranscription()
        #expect(review.voice != nil && review.voice?.transcript == nil)
    }

    @Test func savingKeepsTheVoiceNoteAsItsOwnFile() async throws {
        let container = try MimoDaysStore.makeContainer(inMemory: true)
        let store = try MediaStore(root: FileManager.default.temporaryDirectory.appending(path: "VoiceNoteTests-media-\(UUID().uuidString)"))
        let review = try await review()
        let recording = try record(6, into: review)
        await review.finishTranscription()

        let saver = MomentSaver(context: container.mainContext, store: store, clock: TestDateProvider(), freeBytes: { nil })
        let moment = try await saver.save(review.momentDraft)
        review.clearDraft()

        let note = try #require(moment.voiceNotes.first)
        #expect(moment.voiceNotes.count == 1)
        #expect(abs(note.duration - 6) < 0.2)
        #expect(note.recordedAt == recording.startedAt)
        #expect(note.transcript == "Look, the first snow")
        #expect(note.relativePath.hasPrefix("originals/") && note.relativePath.hasSuffix(".m4a"))
        #expect(try store.orphans(referenced: Set(moment.media.map(\.relativePath) + [note.relativePath])).isEmpty)
        // The clip's own sound is untouched: the voice note isn't one of the moment's media.
        #expect(!moment.media.contains { $0.relativePath == note.relativePath })
        #expect(!FileManager.default.fileExists(atPath: recording.url.path))
    }
}
