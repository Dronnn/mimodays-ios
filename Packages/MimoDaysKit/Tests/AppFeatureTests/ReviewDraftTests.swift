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
            : .photo(try await engine.capturePhoto(flash: false, silent: true))
        return CaptureResult(media: media, window: .init(corner: .bottomLeft), capturedAt: time)
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
