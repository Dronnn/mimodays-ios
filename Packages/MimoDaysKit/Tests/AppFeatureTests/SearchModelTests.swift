@testable import AppFeature
@testable import Core
import Foundation
import Persistence
import SwiftData
import Testing
import TestSupport

/// 9.6 Search (M08/M08b/M09): every word somewhere, where it matched, filters, places.
@MainActor
struct SearchModelTests {
    private static func entry(
        day: Int = 20261018, video: Bool = false, favorite: Bool = false,
        caption: String? = nil, note: String? = nil, transcript: String? = nil, voice: Bool? = nil, place: String? = nil
    ) -> SearchEntry {
        SearchEntry(
            item: MemoryItem(
                id: UUID(), localDay: day, capturedAt: .now, timeZoneID: "UTC", mediaType: video ? .video : .photo,
                origin: .manual, isFavorite: favorite
            ),
            caption: caption, note: note, transcript: transcript, place: place, hasVoiceNote: voice ?? (transcript != nil)
        )
    }

    @Test func everyWordHasToBeFoundSomewhere() {
        let both = Self.entry(caption: "Snow day", place: "Lake Tahoe")
        let one = Self.entry(caption: "Snow day", place: "Yerevan")
        let hits = SearchModel.hits([both, one], query: "snow  tahoe", filters: SearchFilters())
        #expect(hits.map(\.id) == [both.item.id])
        #expect(hits.first?.field == .caption && hits.first?.text == "Snow day")
    }

    @Test func caseAndAccentsDontMatter() {
        let cafe = Self.entry(note: "Breakfast at the Café Central")
        #expect(SearchModel.hits([cafe], query: "CAFE", filters: SearchFilters()).count == 1)
    }

    @Test func aRowSaysWhereItMatchedAndShowsThoseWords() {
        let note = Self.entry(caption: "Ducks", note: "We went to the park and fed the ducks at the lake, Lena fed all the bread")
        let voice = Self.entry(transcript: "then we walked around the lake twice")
        let place = Self.entry(caption: "Sunset", place: "Lake Merritt")
        let hits = SearchModel.hits([note, voice, place], query: "lake", filters: SearchFilters())
        #expect(hits.map(\.field) == [.note, .voiceNote, .place])
        #expect(hits[0].text?.hasPrefix("…") == true && hits[0].text?.contains("the lake, Lena") == true)
        #expect(hits[1].text == "“…we walked around the lake twice”")
        #expect(hits[2].text == "Sunset")
    }

    @Test func onlyFiltersListEveryMomentTheyLeave() {
        let photo = Self.entry(caption: "Photo")
        let video = Self.entry(video: true, note: "A video")
        let videos = SearchModel.hits([photo, video], query: " ", filters: SearchFilters(kind: .videos))
        #expect(videos.map(\.id) == [video.item.id] && videos.first?.field == nil && videos.first?.text == "A video")
    }

    @Test func filtersNarrowByKindDaysVoiceNoteFavoriteAndPlace() {
        let entries = [
            Self.entry(day: 20260101, caption: "a"),
            Self.entry(day: 20260601, video: true, caption: "a", voice: true),
            Self.entry(day: 20261018, favorite: true, caption: "a", note: "written", place: "Yerevan"),
        ]
        func ids(_ filters: SearchFilters) -> [UUID] { SearchModel.hits(entries, query: "a", filters: filters).map(\.id) }
        #expect(ids(SearchFilters(kind: .photos)) == [entries[0].item.id, entries[2].item.id])
        #expect(ids(SearchFilters(from: 20260201, to: 20260701)) == [entries[1].item.id])
        #expect(ids(SearchFilters(hasVoiceNote: true)) == [entries[1].item.id])
        #expect(ids(SearchFilters(hasWrittenNote: true)) == [entries[2].item.id])
        #expect(ids(SearchFilters(favoritesOnly: true)) == [entries[2].item.id])
        #expect(ids(SearchFilters(place: "Yerevan")) == [entries[2].item.id])
        #expect(SearchFilters(kind: .videos, hasVoiceNote: true, place: "Yerevan").count == 3)
    }

    @Test func placesAreCountedWithTheirLatestYear() {
        let entries = [
            Self.entry(day: 20240710, place: "Lake Tahoe"), Self.entry(day: 20240711, place: "Lake Tahoe"),
            Self.entry(day: 20261018, place: "Lake Merritt"), Self.entry(day: 20261018, place: "Yerevan"),
        ]
        let places = SearchModel.places(entries, query: "lake", filters: SearchFilters())
        #expect(places == [PlaceHit(label: "Lake Tahoe", count: 2, latestYear: 2024), PlaceHit(label: "Lake Merritt", count: 1, latestYear: 2026)])
        #expect(SearchModel.places(entries, query: "", filters: SearchFilters()).isEmpty)
        #expect(SearchModel.places(entries, query: "lake", filters: SearchFilters(place: "Lake Tahoe")).isEmpty)
    }

    @Test func theStoreIsReadWithPlacesAndVoiceNoteWords() async throws {
        let container = try MimoDaysStore.makeContainer(inMemory: true)
        let root = FileManager.default.temporaryDirectory.appending(path: "Search-\(UUID().uuidString)")
        let store = try MediaStore(root: root)
        let engine = SimulatedCaptureEngine()
        _ = await engine.start()
        let saver = MomentSaver(context: container.mainContext, store: store, clock: TestDateProvider(), freeBytes: { nil })
        for (caption, place, transcript) in [("Ducks", "Lake Merritt", nil), ("", nil, "we walked around the lake twice"), ("Gone", "Lake Tahoe", nil)] {
            let capture = CaptureResult(
                media: .photo(try await engine.capturePhoto(flash: false, silent: true)), window: .init(),
                capturedAt: CaptureTime(instant: .now, timeZone: .gmt)
            )
            var draft = MomentDraft(
                capture: capture, caption: caption,
                window: SelfieWindowFrame(frame: CGRect(x: 266.7, y: 111.1, width: 112, height: 150), preview: CGSize(width: 402, height: 536)), promptID: nil,
                place: place.map { ReviewPlace(label: $0, latitude: 37.8, longitude: -122.2, precision: .city, source: .gps) }
            )
            if let transcript {
                let url = root.appending(path: "\(UUID().uuidString).m4a")
                try SimulatedVoiceRecorder.writeTone(to: url, seconds: 1)
                draft.voice = ReviewVoiceNote(url: url, duration: 1, recordedAt: .now, transcript: transcript)
            }
            _ = try await saver.save(draft)
        }
        try container.mainContext.fetch(FetchDescriptor<Moment>(predicate: #Predicate { $0.title == "Gone" })).first?.deletedAt = .now
        let model = SearchModel(library: MediaLibrary(context: container.mainContext, store: store, thumbnails: ThumbnailPipeline()))
        model.refresh()
        #expect(model.entries.count == 2)
        model.query = "lake"
        #expect(Set(model.hits.compactMap(\.field)) == [.place, .voiceNote])
        #expect(model.places.map(\.label) == ["Lake Merritt"])
        model.show(place: "Lake Merritt")
        #expect(model.query.isEmpty && model.hits.map(\.entry.caption) == ["Ducks"])
        #expect(model.filteredCount == 1)
        model.clearFilters()
        #expect(model.filters.isEmpty && !model.isSearching)
    }
}
