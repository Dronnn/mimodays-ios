@testable import AppFeature
@testable import Core
import Foundation
import Testing

/// 7.2: a review survives the app being closed: capture files and what was added, until saved or retaken.
@MainActor
struct ReviewDraftTests {
    private let drafts = ReviewDraftStore(root: FileManager.default.temporaryDirectory.appending(path: "ReviewDraftTests-\(UUID().uuidString)"))
    private let time = CaptureTime(instant: Date(timeIntervalSince1970: 1_000), timeZone: .gmt)

    private func capture(video: Bool = false) async throws -> CaptureResult {
        let engine = SimulatedCaptureEngine()
        _ = await engine.start()
        let media: CaptureResult.Media = video
            ? .video(try await engine.record(limit: .seconds(1)))
            : .photo(try await engine.capturePhoto(flash: .off, silent: true))
        return CaptureResult(media: media, window: .init(corner: .bottomLeft), capturedAt: time)
    }

    /// iOS ended the app after the capture moved in but before its draft was written, or a draft lost its main file:
    /// at launch nothing private stays behind. A draft that reopens keeps its files.
    @Test func filesNoDraftPointsToGoAtLaunch() async throws {
        defer { drafts.clear() }
        _ = try drafts.adopt(try await capture())
        drafts.removeLeftovers()
        #expect(!FileManager.default.fileExists(atPath: drafts.root.path))

        let review = ReviewModel(capture: try drafts.adopt(try await capture()), drafts: drafts)
        review.caption = "kept"
        let stray = drafts.root.appending(path: "stray.jpg")
        try Data([1]).write(to: stray)
        drafts.removeLeftovers()
        #expect(!FileManager.default.fileExists(atPath: stray.path))
        #expect(drafts.load()?.caption == "kept")
        #expect(FileManager.default.fileExists(atPath: review.capture.mainURL.path))
    }

    @Test func adoptingMovesTheFilesOutOfTemporaryStorage() async throws {
        defer { drafts.clear() }
        let original = try await capture()
        let adopted = try drafts.adopt(original)
        #expect(adopted.mainURL.deletingLastPathComponent().standardizedFileURL == drafts.root.standardizedFileURL)
        #expect(FileManager.default.fileExists(atPath: adopted.mainURL.path))
        #expect(FileManager.default.fileExists(atPath: try #require(adopted.selfieURL).path))
        #expect(!FileManager.default.fileExists(atPath: original.mainURL.path))
    }

    @Test func everyChangeIsKeptAndComesBackAfterARelaunch() async throws {
        defer { drafts.clear() }
        let promptID = UUID()
        let review = ReviewModel(capture: try drafts.adopt(try await capture(video: true)), promptID: promptID, drafts: drafts)
        review.caption = "Lena"
        review.note = "She shouted \"don't let go\" for the whole street"
        review.window.corner = .topLeft

        let draft = try #require(drafts.load())
        let restored = ReviewModel(draft: draft, drafts: drafts)
        #expect(restored.caption == "Lena")
        #expect(restored.note == review.note)
        #expect(restored.window.corner == .topLeft)
        #expect(restored.promptID == promptID)
        #expect(restored.capture == review.capture)
        #expect(restored.video != nil && restored.hasSelfie)
    }

    @Test func filesAreFoundAgainWhenTheAppContainerMoved() async throws {
        defer { drafts.clear() }
        var capture = try drafts.adopt(try await capture())
        let names = [capture.mainURL.lastPathComponent, capture.selfieURL?.lastPathComponent]
        // As if written by an older install at another path.
        try capture.mapFiles { URL(filePath: "/old/container/Review").appending(path: $0.lastPathComponent) }
        drafts.save(ReviewDraft(capture: capture, window: .init()))
        let loaded = try #require(drafts.load())
        #expect([loaded.capture.mainURL.lastPathComponent, loaded.capture.selfieURL?.lastPathComponent] == names)
        #expect(FileManager.default.fileExists(atPath: loaded.capture.mainURL.path))
    }

    @Test func aMissingSelfieIsDroppedAndAMissingMainDropsTheDraft() async throws {
        defer { drafts.clear() }
        let review = ReviewModel(capture: try drafts.adopt(try await capture()), drafts: drafts)
        try FileManager.default.removeItem(at: try #require(review.capture.selfieURL))
        let withoutSelfie = try #require(drafts.load())
        #expect(withoutSelfie.capture.selfieURL == nil && withoutSelfie.capture.window == nil)
        try FileManager.default.removeItem(at: review.capture.mainURL)
        #expect(drafts.load() == nil)
    }

    @Test func retakeAndSaveLeaveNothingBehind() async throws {
        let review = ReviewModel(capture: try drafts.adopt(try await capture()), drafts: drafts)
        #expect(drafts.load() != nil)
        review.discard()
        #expect(drafts.load() == nil)
        #expect(!FileManager.default.fileExists(atPath: drafts.root.path))

        let saved = ReviewModel(capture: try drafts.adopt(try await capture()), drafts: drafts)
        saved.clearDraft()
        #expect(drafts.load() == nil)
    }

    /// A retaken review changed late (a place lookup finishing) doesn't write over the next capture's draft.
    @Test func aRetakenReviewDoesntWriteOverTheNextDraft() async throws {
        defer { drafts.clear() }
        let old = ReviewModel(capture: try drafts.adopt(try await capture()), drafts: drafts)
        old.discard()
        let next = ReviewModel(capture: try drafts.adopt(try await capture()), drafts: drafts)
        old.caption = "Late"
        let draft = try #require(drafts.load())
        #expect(draft.capture == next.capture && draft.caption == "")
    }

    /// A Review left open behind a link (never retaken itself) whose recovered twin was retaken: when its late
    /// change lands, the next capture's draft stays.
    @Test func aReviewLeftBehindDoesntWriteOverTheNextDraft() async throws {
        defer { drafts.clear() }
        let left = ReviewModel(capture: try drafts.adopt(try await capture()), drafts: drafts)
        let twin = ReviewModel(draft: try #require(drafts.load()), drafts: drafts)
        twin.discard()
        let next = ReviewModel(capture: try drafts.adopt(try await capture()), drafts: drafts)
        next.caption = "Next"
        left.caption = "Late"
        let draft = try #require(drafts.load())
        #expect(draft.capture == next.capture && draft.caption == "Next")
        // Before the next capture came, it brought back no draft whose files are gone either.
        twin.caption = "Gone"
        #expect(drafts.load()?.caption == "Next")
    }

    @Test func theNoteIsCappedAndCountsAsSomethingToKeep() async throws {
        let review = ReviewModel(capture: try await capture())
        defer { review.discard() }
        #expect(!review.hasAnnotations)
        review.note = String(repeating: "a", count: 600)
        #expect(review.note.count == ReviewModel.noteLimit)
        #expect(review.hasAnnotations)
        #expect(review.momentDraft.note == review.note)
    }
}
