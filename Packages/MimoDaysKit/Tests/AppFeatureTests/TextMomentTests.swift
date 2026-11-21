@testable import AppFeature
import Core
import Foundation
import Persistence
import SwiftData
import Testing
import TestSupport

/// P8.11: a moment in words only, saved without any file.
@MainActor
struct TextMomentTests {
    private let container = try! TestStore.container()
    private let store: MediaStore
    private let now = Date(timeIntervalSince1970: 1_794_398_400)

    init() throws {
        store = try MediaStore(root: FileManager.default.temporaryDirectory.appending(path: "TextMoment-\(UUID().uuidString)"))
    }

    private var saver: MomentSaver { MomentSaver(context: container.mainContext, store: store, clock: TestDateProvider(now), freeBytes: { nil }) }

    private func draft(_ body: String, caption: String = "") -> TextMomentDraft {
        TextMomentDraft(capturedAt: CaptureTime(instant: now, timeZone: TimeZone(identifier: "Asia/Yerevan")!), caption: caption, body: body)
    }

    @Test func limitsAndTrimming() {
        #expect(TextMoment.cleaned("  hello \n", limit: 500) == "hello")
        #expect(TextMoment.cleaned(String(repeating: "a", count: 600), limit: 500).count == 500)
        // Whole characters: an emoji is never cut in half.
        #expect(TextMoment.cleaned(String(repeating: "👋🏽", count: 90), limit: 80) == String(repeating: "👋🏽", count: 80))
        #expect(!TextMoment.canSave(draft(" \n ")))
        #expect(TextMoment.canSave(draft("A walk by the lake")))
    }

    @Test func theExcerptIsOneLineAndShort() {
        #expect(TextMoment.excerpt("First line\n\nsecond line") == "First line second line")
        let long = String(repeating: "word ", count: 60)
        let excerpt = TextMoment.excerpt(long)
        #expect(excerpt.hasSuffix("…") && excerpt.count <= TextMoment.excerptLimit + 1)
        #expect(!excerpt.dropLast().hasSuffix(" "))
    }

    /// Share text: the caption over the words, nothing more.
    @Test func sharedTextIsTheCaptionAndTheWords() {
        #expect(TextMoment.shareText(title: "Rain day", body: "Blanket fort.\nThree chapters.") == "Rain day\n\nBlanket fort.\nThree chapters.")
        #expect(TextMoment.shareText(title: nil, body: "Only words") == "Only words")
        #expect(TextMoment.shareText(title: " ", body: "Words") == "Words")
    }

    /// Body in the note, caption in the title, a manual moment with no media and nothing in the store.
    @Test func itSavesWithoutAnyFile() throws {
        var draft = draft("  We found the old bakery again.\n", caption: " Bakery ")
        draft.tags = ["walks"]
        draft.mood = .joyful
        draft.place = ReviewPlace.current(city: "Yerevan", at: GeoPoint(latitude: 40.18, longitude: 44.51, horizontalAccuracy: 10))
        let moment = try saver.saveText(draft)
        #expect(moment.mediaType == .text && moment.origin == .manual && moment.promptID == nil)
        #expect(moment.note == "We found the old bakery again." && moment.title == "Bakery")
        #expect(moment.media.isEmpty)
        #expect(moment.tags == ["walks"] && moment.mood == .joyful)
        #expect(moment.location?.placeLabel == "Yerevan")
        #expect(moment.localDay == 20261111)
        #expect(try store.orphans(referenced: []).isEmpty)
        #expect(throws: SaveError.failed) { try saver.saveText(self.draft("   ")) }
        #expect(try container.mainContext.fetch(FetchDescriptor<Moment>()).count == 1)
    }

    /// Search's Text filter keeps written moments only.
    @Test func theTextFilter() {
        let photo = SearchEntry(
            item: MemoryItem(id: UUID(), localDay: 20261111, capturedAt: now, timeZoneID: "UTC", mediaType: .photo, origin: .manual, isFavorite: false),
            caption: "lake", note: nil, transcript: nil, place: nil, hasVoiceNote: false, collections: []
        )
        let text = SearchEntry(
            item: MemoryItem(id: UUID(), localDay: 20261111, capturedAt: now, timeZoneID: "UTC", mediaType: .text, origin: .manual, isFavorite: false),
            caption: nil, note: "by the lake at dawn", transcript: nil, place: nil, hasVoiceNote: false, collections: []
        )
        #expect(SearchModel.hits([photo, text], query: "lake", filters: SearchFilters(kind: .text)).map(\.id) == [text.item.id])
        #expect(SearchModel.hits([photo, text], query: "dawn", filters: SearchFilters()).map(\.id) == [text.item.id])
    }

    /// One second per day counts a written moment as the day's.
    @Test func oneSecondPerDayCountsIt() throws {
        let moment = try saver.saveText(draft("Rain all day"))
        let days = try MoviesModel.oneSecondDays(in: container.mainContext, store: store, days: OneSecondPerDay.days(ofMonth: 202611))
        #expect(days.map(\.picked) == [moment.id])
    }
}
