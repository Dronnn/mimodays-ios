@testable import AppFeature
import Core
import Foundation
import Persistence
import SwiftData
import Testing
import TestSupport

/// P8.11 II01-II03: writing a moment, its draft kept until it's saved or discarded.
@MainActor
struct WriteMomentModelTests {
    private let container = try! TestStore.container()
    private let store: MediaStore
    private let drafts = WritingDraftStore.temporary
    private let now = CaptureTime(instant: Date(timeIntervalSince1970: 1_794_398_400), timeZone: TimeZone(identifier: "Asia/Yerevan")!)

    init() throws {
        store = try MediaStore(root: FileManager.default.temporaryDirectory.appending(path: "WriteMoment-\(UUID().uuidString)"))
    }

    private var saver: MomentSaver {
        MomentSaver(context: container.mainContext, store: store, clock: TestDateProvider(now.instant), freeBytes: { nil })
    }

    /// Every change is on disk at once, and an unfinished moment comes back as it was.
    @Test func theDraftSurvivesAndComesBack() {
        let model = WriteMomentModel(now: now, drafts: drafts)
        model.caption = "Rain day"
        model.body = "Lena and I built a blanket fort"
        model.tags = ["lena"]
        model.mood = .calm
        model.choose(ReviewPlace(label: "Yerevan", latitude: 40.18, longitude: 44.51, precision: .city, source: .manual))
        let kept = try! #require(drafts.load())
        #expect(kept.caption == "Rain day" && kept.body == "Lena and I built a blanket fort")
        #expect(kept.tags == ["lena"] && kept.mood == .calm && kept.place?.label == "Yerevan" && kept.placeWasChosen)
        let reopened = WriteMomentModel(draft: kept, now: CaptureTime(instant: now.instant.addingTimeInterval(600), timeZone: now.timeZone), drafts: drafts)
        // Its time stays when it was started.
        #expect(reopened.draft == kept)
    }

    /// 80 characters of caption, 500 of words; Save needs words in the body.
    @Test func limitsAndSave() {
        let model = WriteMomentModel(now: now, drafts: drafts)
        #expect(!model.canSave && !model.hasEdits)
        model.caption = String(repeating: "a", count: 100)
        #expect(model.caption.count == TextMoment.captionLimit)
        #expect(!model.canSave && model.hasEdits)
        model.body = "  \n "
        #expect(!model.canSave)
        model.body = String(repeating: "b", count: 600)
        #expect(model.body.count == TextMoment.bodyLimit && model.canSave)
    }

    /// Saved: a text moment, and the draft is gone.
    @Test func savingClearsTheDraft() throws {
        let model = WriteMomentModel(now: now, drafts: drafts)
        model.body = "Rain all day"
        let moment = try model.save(with: saver)
        #expect(moment.mediaType == .text && moment.note == "Rain all day")
        #expect(drafts.load() == nil)
        // Nothing written after it.
        model.body = "more"
        #expect(drafts.load() == nil)
    }

    /// A failed save keeps the words for Try again.
    @Test func aFailedSaveKeepsTheDraft() {
        let model = WriteMomentModel(now: now, drafts: drafts)
        model.caption = "Only a caption"
        #expect(throws: SaveError.failed) { try model.save(with: saver) }
        #expect(drafts.load()?.caption == "Only a caption")
    }

    @Test func discardingClearsTheDraft() {
        let model = WriteMomentModel(now: now, drafts: drafts)
        model.body = "Never mind"
        model.discard()
        #expect(drafts.load() == nil)
    }

    /// The city fills in by itself, unless a place (or No place) was picked first.
    @Test func theCityFillsInUnlessOneWasPicked() async {
        let model = WriteMomentModel(now: now, drafts: drafts, places: .simulated)
        await model.locate()
        #expect(model.place?.label == "Yerevan" && !model.placeWasChosen && !model.hasEdits)
        let picked = WriteMomentModel(now: now, drafts: drafts, places: .simulated)
        picked.choose(nil)
        await picked.locate()
        #expect(picked.place == nil)
    }
}
