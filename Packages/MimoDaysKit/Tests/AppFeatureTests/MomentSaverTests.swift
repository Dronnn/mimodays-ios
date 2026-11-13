@testable import AppFeature
@testable import Core
import Foundation
import Persistence
import SwiftData
import Testing
import TestSupport

/// 7.5 / 7.7: the save path. Media and record land together or not at all.
@MainActor
struct MomentSaverTests {
    private let container: ModelContainer
    private let store: MediaStore
    private let root: URL
    private let time = CaptureTime(instant: Date(timeIntervalSince1970: 1_794_407_820), timeZoneID: "Asia/Yerevan")
    private let window = SelfieWindowFrame(frame: CGRect(x: 266.7, y: 111.1, width: 112, height: 150), preview: CGSize(width: 402, height: 536))

    init() throws {
        container = try MimoDaysStore.makeContainer(inMemory: true)
        root = FileManager.default.temporaryDirectory.appending(path: "MomentSaverTests-\(UUID().uuidString)")
        store = try MediaStore(root: root)
    }

    private func saver(freeBytes: Int64? = nil) -> MomentSaver {
        MomentSaver(context: container.mainContext, store: store, clock: TestDateProvider(), freeBytes: { freeBytes })
    }

    private func photo(swapped: Bool = false) async throws -> CaptureResult {
        let engine = SimulatedCaptureEngine()
        _ = await engine.start()
        var photo = try await engine.capturePhoto(flash: false, silent: true)
        if swapped, let selfie = photo.selfieURL {
            photo = CapturedPhoto(mainURL: selfie, mainPosition: .front, selfieURL: photo.mainURL)
        }
        return CaptureResult(media: .photo(photo), window: .init(), capturedAt: time)
    }

    private func video() async throws -> CaptureResult {
        let engine = SimulatedCaptureEngine()
        _ = await engine.start()
        var video = try await engine.record(limit: .seconds(1))
        video.selfieOffset = 0.04
        return CaptureResult(media: .video(video), window: .init(), capturedAt: time)
    }

    private func moments() throws -> [Moment] {
        try container.mainContext.fetch(FetchDescriptor<Moment>())
    }

    @Test func aPhotoKeepsBothSourcesTheCompositeAndAThumbnail() async throws {
        let capture = try await photo()
        let moment = try await saver().save(MomentDraft(
            capture: capture, caption: "  Lena on her bike ", note: "She shouted \"don't let go\"\n", window: window, promptID: nil
        ))

        #expect(try moments().count == 1)
        #expect(moment.mediaType == .photo && moment.origin == .manual && moment.promptID == nil)
        #expect(moment.title == "Lena on her bike")
        #expect(moment.note == "She shouted \"don't let go\"")
        #expect(moment.timeZoneID == "Asia/Yerevan" && moment.localDay == 20261111)
        #expect(Set(moment.media.map(\.role)) == [.rearSource, .frontSource, .composedPreview, .thumbnail])
        for media in moment.media {
            #expect(try store.verify(media.relativePath, checksum: media.checksum), "\(media.role)")
        }
        let rear = try #require(moment.media.first { $0.role == .rearSource })
        #expect(rear.pixelWidth == 900 && rear.pixelHeight == 1200)
        #expect(rear.relativePath.hasPrefix("originals/"))
        #expect(try #require(moment.media.first { $0.role == .thumbnail }).relativePath.hasPrefix("derived/"))
        let layout = try #require(moment.pipLayout)
        #expect(layout.source == .frontSource)
        #expect(abs(layout.centerX - window.frame.midX / 402) < 0.0001)
        // The temporary capture files are gone once the moment is kept.
        #expect(!FileManager.default.fileExists(atPath: capture.mainURL.path))
    }

    @Test func aSwappedPhotoRemembersTheRearCameraIsInTheWindow() async throws {
        let moment = try await saver().save(MomentDraft(capture: try await photo(swapped: true), caption: "", window: window, promptID: nil))
        #expect(moment.title == nil && moment.note == nil)
        #expect(moment.pipLayout?.source == .rearSource)
        #expect(try #require(moment.media.first { $0.role == .frontSource }).pixelWidth == 360)
    }

    @Test func aVideoKeepsStreamsAndTimingWithoutAComposedFile() async throws {
        let capture = try await video()
        let promptID = UUID()
        let moment = try await saver().save(MomentDraft(capture: capture, caption: "", window: window, promptID: promptID))
        #expect(moment.mediaType == .video && moment.origin == .randomPrompt && moment.promptID == promptID)
        #expect(Set(moment.media.map(\.role)) == [.rearSource, .frontSource, .thumbnail])
        let rear = try #require(moment.media.first { $0.role == .rearSource })
        let front = try #require(moment.media.first { $0.role == .frontSource })
        #expect(rear.startOffset == nil && front.startOffset == 0.04)
        #expect(abs((rear.duration ?? 0) - 1) < 0.2)
        #expect(rear.codec != nil && !rear.hasAudio)
        #expect(rear.pixelWidth == 450 && rear.pixelHeight == 600)
        // The saved layout gives back the window the clip is composed with.
        let restored = try #require(moment.pipLayout).windowFrame(in: window.preview)
        #expect(abs(restored.frame.minX - window.frame.minX) < 0.01 && abs(restored.frame.minY - window.frame.minY) < 0.01)
        #expect(abs(restored.frame.height - window.frame.height) < 0.01)
    }

    @Test func tooLittleSpaceKeepsTheCaptureAndWritesNothing() async throws {
        let capture = try await photo()
        defer { capture.discardFiles() }
        await #expect(throws: SaveError.self) {
            _ = try await saver(freeBytes: 10_000_000).save(MomentDraft(capture: capture, caption: "", window: window, promptID: nil))
        }
        do {
            _ = try await saver(freeBytes: 10_000_000).save(MomentDraft(capture: capture, caption: "", window: window, promptID: nil))
        } catch let SaveError.lowStorage(shortfall) {
            #expect(shortfall > MomentSaver.reserve - 10_000_000)
        }
        #expect(try moments().isEmpty)
        #expect(try store.orphans(referenced: []).isEmpty)
        #expect(FileManager.default.fileExists(atPath: capture.mainURL.path))
    }

    @Test func aFailurePartWayRemovesWhatWasWrittenAndKeepsTheRest() async throws {
        let capture = try await photo()
        defer { capture.discardFiles() }
        // The selfie file disappears before the save: the main copy is rolled back, nothing is recorded.
        try FileManager.default.removeItem(at: try #require(capture.selfieURL))
        await #expect(throws: SaveError.failed) {
            _ = try await saver().save(MomentDraft(capture: capture, caption: "", window: window, promptID: nil))
        }
        #expect(try moments().isEmpty)
        #expect(try store.orphans(referenced: []).isEmpty)
        #expect(FileManager.default.fileExists(atPath: capture.mainURL.path))
    }

    @Test func aVoiceNoteThatCannotBeCopiedRollsBackEveryFile() async throws {
        let capture = try await photo()
        defer { capture.discardFiles() }
        // The voice note is copied last: its file is gone, so the sources, composite and thumbnail already written go too.
        let voice = ReviewVoiceNote(url: root.appending(path: "missing.m4a"), duration: 3, recordedAt: .now, transcript: nil)
        var draft = MomentDraft(capture: capture, caption: "", window: window, promptID: nil)
        draft.voice = voice
        await #expect(throws: SaveError.failed) { _ = try await saver().save(draft) }
        #expect(try moments().isEmpty)
        #expect(try store.orphans(referenced: []).isEmpty)
        #expect(FileManager.default.fileExists(atPath: capture.mainURL.path))
    }

    @Test func aMomentWithoutASelfieHasNoWindow() async throws {
        let engine = SimulatedCaptureEngine(multiCam: false)
        _ = await engine.start()
        let photo = try await engine.capturePhoto(flash: false, silent: true)
        let capture = CaptureResult(media: .photo(photo), window: nil, capturedAt: time)
        let moment = try await saver().save(MomentDraft(capture: capture, caption: "", window: nil, promptID: nil))
        #expect(moment.pipLayout == nil)
        #expect(Set(moment.media.map(\.role)) == [.rearSource, .thumbnail])
    }
}
