@testable import AppFeature
@testable import Core
import DesignSystem
import Foundation
import Persistence
import SwiftData
import SwiftUI
import Testing
import TestSupport

/// Search (M08 results, M08b filters, M09 no matches), from moments saved off the simulated camera.
@MainActor
@Suite(.tags(.snapshot))
struct SearchSnapshotTests {
    private let container = try! MimoDaysStore.makeContainer(inMemory: true)
    private let root = FileManager.default.temporaryDirectory.appending(path: "SearchSnapshots-\(UUID().uuidString)")
    private let store: MediaStore

    /// The view's `.task` can still run after a test returns; its store must outlive the test.
    private static var stores: [ModelContainer] = []

    init() throws {
        store = try MediaStore(root: root)
        Self.stores.append(container)
    }

    private static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    private func populate() async throws {
        let engine = SimulatedCaptureEngine()
        _ = await engine.start()
        let saver = MomentSaver(context: container.mainContext, store: store, clock: TestDateProvider(), freeBytes: { nil })
        let moments: [(Date, String, String, String?, String?)] = [
            (Self.date(2026, 10, 18), "", "Ducks at the lake, Lena fed all the bread", "Lake Merritt", nil),
            (Self.date(2026, 9, 5), "", "", nil, "and then we walked around the lake twice before dinner"),
            (Self.date(2026, 8, 2), "Lake Merritt, sunset", "", "Lake Merritt", nil),
            (Self.date(2024, 7, 11), "Swimming with grandpa", "", "Lake Tahoe", nil),
            (Self.date(2024, 7, 12), "", "", "Lake Tahoe", nil),
        ]
        for (date, caption, note, place, transcript) in moments {
            let capture = CaptureResult(
                media: .photo(try await engine.capturePhoto(flash: false, silent: true)), window: .init(),
                capturedAt: CaptureTime(instant: date, timeZone: .gmt)
            )
            var draft = MomentDraft(
                capture: capture, caption: caption,
                window: SelfieWindowFrame(frame: CGRect(x: 266.7, y: 111.1, width: 112, height: 150), preview: CGSize(width: 402, height: 536)),
                promptID: nil,
                place: place.map { ReviewPlace(label: $0, latitude: 37.8, longitude: -122.2, precision: .city, source: .gps) }
            )
            draft.note = note
            if let transcript {
                let url = root.appending(path: "\(UUID().uuidString).m4a")
                try SimulatedVoiceRecorder.writeTone(to: url, seconds: 1)
                draft.voice = ReviewVoiceNote(url: url, duration: 1, recordedAt: date, transcript: transcript)
            }
            _ = try await saver.save(draft)
        }
    }

    private func model(query: String, filters: SearchFilters = SearchFilters()) async throws -> SearchModel {
        try await populate()
        let clock = TestDateProvider()
        clock.set(Self.date(2026, 11, 11))
        let model = SearchModel(
            library: MediaLibrary(context: container.mainContext, store: store, thumbnails: ThumbnailPipeline()), clock: clock,
            calendar: { Calendar(identifier: .gregorian) }
        )
        model.refresh()
        model.query = query
        model.filters = filters
        for hit in model.hits { await model.load(hit.id) }
        return model
    }

    private func screen(_ model: SearchModel) -> some View {
        NavigationStack { SearchView(model: model) }
    }

    /// M08.
    @Test func results() async throws {
        assertScreenSnapshots(of: screen(try await model(query: "lake")), variants: [
            SnapshotVariant(.iPhone, .light), SnapshotVariant(.iPhone, .dark), SnapshotVariant(.iPhone, .light, .accessibilityExtraLarge),
            SnapshotVariant(.iPhone, .light, rightToLeft: true), SnapshotVariant(.iPad, .light),
        ])
    }

    /// M09.
    @Test func noMatches() async throws {
        assertScreenSnapshots(of: screen(try await model(query: "snow tahoe", filters: SearchFilters(kind: .videos))), variants: [
            SnapshotVariant(.iPhone, .light), SnapshotVariant(.iPhone, .dark), SnapshotVariant(.iPhone, .light, .accessibilityExtraLarge),
        ])
    }

    /// M08b, on its own.
    @Test func filters() async throws {
        let model = try await model(query: "lake", filters: SearchFilters(hasVoiceNote: true))
        assertScreenSnapshots(
            of: SearchFiltersSheet(model: model).background(ColorToken.surfaceSheet.color.ignoresSafeArea()),
            variants: [SnapshotVariant(.iPhone, .light), SnapshotVariant(.iPhone, .dark), SnapshotVariant(.iPhone, .light, .accessibilityExtraLarge)]
        )
    }
}
