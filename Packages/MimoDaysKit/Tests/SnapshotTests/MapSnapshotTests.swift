@testable import AppFeature
@testable import Core
import DesignSystem
import Foundation
import Persistence
import SwiftData
import SwiftUI
import Testing
import TestSupport

/// Map pieces without a live map (MapKit tiles don't draw offscreen; the UI tests cover P01 and P03):
/// P02's sheet, P04's filters, P05's card, P05b's moments without a place.
@MainActor
@Suite(.tags(.snapshot))
struct MapSnapshotTests {
    private let container = try! MimoDaysStore.makeContainer(inMemory: true)
    private let store: MediaStore

    /// The view's `.task` can still run after a test returns; its store must outlive the test.
    private static var stores: [ModelContainer] = []

    init() throws {
        store = try MediaStore(root: FileManager.default.temporaryDirectory.appending(path: "MapSnapshots-\(UUID().uuidString)"))
        Self.stores.append(container)
    }

    private var library: MediaLibrary { MediaLibrary(context: container.mainContext, store: store, thumbnails: ThumbnailPipeline()) }

    /// Moments off the simulated camera, a month apart from August 2026, at `place` when one is given.
    private func save(_ count: Int, at place: String? = nil, video: Int? = nil) async throws -> [UUID] {
        let engine = SimulatedCaptureEngine()
        _ = await engine.start()
        let saver = MomentSaver(context: container.mainContext, store: store, clock: TestDateProvider(), freeBytes: { nil })
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        var ids: [UUID] = []
        for index in 0..<count {
            let date = calendar.date(from: DateComponents(year: 2026, month: 8 + index % 4, day: 1 + index, hour: 12))!
            let media: CaptureResult.Media = index == video
                ? .video(try await engine.record(limit: .seconds(1)))
                : .photo(try await engine.capturePhoto(flash: false, silent: true))
            let capture = CaptureResult(media: media, window: .init(), capturedAt: CaptureTime(instant: date, timeZone: .gmt))
            let draft = MomentDraft(
                capture: capture, caption: "",
                window: SelfieWindowFrame(frame: CGRect(x: 266.7, y: 111.1, width: 112, height: 150), preview: CGSize(width: 402, height: 536)),
                promptID: nil,
                place: place.map { ReviewPlace(label: $0, latitude: 37.80, longitude: -122.26, precision: .exact, source: .manual) }
            )
            ids.append(try await saver.save(draft).id)
        }
        return ids
    }

    /// P02.
    @Test func placePreview() async throws {
        try await save(5, at: "Lake Merritt", video: 2)
        let model = MapModel(library: library)
        model.refresh()
        let place = try #require(model.places.first)
        for moment in place.moments { await model.load(moment.id) }
        assertScreenSnapshots(
            of: PlacePreviewSheet(model: model, place: place, open: { _ in }, seeAll: {})
                .frame(maxHeight: .infinity, alignment: .bottom)
                .background(ColorToken.surfaceSheet.color.ignoresSafeArea()),
            variants: [SnapshotVariant(.iPhone, .light), SnapshotVariant(.iPhone, .dark), SnapshotVariant(.iPhone, .light, .accessibilityExtraLarge)]
        )
    }

    /// P01's Recent places panel; at larger text its header stacks.
    @Test func recentPlaces() async throws {
        try await save(2, at: "Lake Merritt")
        try await save(1, at: "Grandma's")
        let model = MapModel(library: library)
        model.refresh()
        for place in model.recentPlaces { if let id = place.moments.first?.id { await model.load(id) } }
        assertScreenSnapshots(
            of: NavigationStack {
                RecentPlacesPanel(model: model) { _ in }
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .background(ColorToken.canvas.color.ignoresSafeArea())
            },
            variants: [SnapshotVariant(.iPhone, .light), SnapshotVariant(.iPhone, .dark), SnapshotVariant(.iPhone, .light, .accessibilityExtraLarge)]
        )
    }

    /// P04.
    @Test func filters() async throws {
        let ids = try await save(3, at: "Lake Merritt")
        let summer = try #require(try CollectionStore(context: container.mainContext).create("Summer 2026", with: ids))
        let model = MapModel(library: library)
        model.refresh()
        // As drawn: a custom period and a collection.
        model.filters.from = 20260601
        model.filters.to = 20260831
        model.filters.collection = summer
        assertScreenSnapshots(
            of: MapFiltersSheet(model: model, thisYear: 2026).background(ColorToken.surfaceSheet.color.ignoresSafeArea()),
            variants: [SnapshotVariant(.iPhone, .light), SnapshotVariant(.iPhone, .dark), SnapshotVariant(.iPhone, .light, .accessibilityExtraLarge)]
        )
    }

    /// P05's card, location off (the veiled map under it is MapKit's, which doesn't draw offscreen).
    @Test func noPlaces() {
        assertScreenSnapshots(
            of: NavigationStack {
                NoPlacesCard(locationIsUsable: false, unlocatedCount: 40) {}
                    .padding(.horizontal, 24)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, 44)
                    .background(ColorToken.canvas.color.ignoresSafeArea())
            },
            variants: [SnapshotVariant(.iPhone, .light), SnapshotVariant(.iPhone, .dark), SnapshotVariant(.iPhone, .light, .accessibilityExtraLarge)]
        )
    }

    /// P05, location on: no button, the other words.
    @Test func noPlacesWithLocation() {
        assertScreenSnapshots(
            of: NoPlacesCard(locationIsUsable: true, unlocatedCount: 0) {}
                .padding(.horizontal, 24)
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, 44)
                .background(ColorToken.canvas.color.ignoresSafeArea()),
            variants: [SnapshotVariant(.iPhone, .light)]
        )
    }

    /// P06: the drawn grid, the card and Try again, then every place.
    @Test func unavailable() async throws {
        try await save(3, at: "Lake Merritt")
        let model = MapModel(library: library)
        model.refresh()
        assertScreenSnapshots(
            of: NavigationStack { MapUnavailableView(model: model) {}.background(ColorToken.canvas.color.ignoresSafeArea()) },
            variants: [SnapshotVariant(.iPhone, .light), SnapshotVariant(.iPhone, .dark), SnapshotVariant(.iPhone, .light, .accessibilityExtraLarge)]
        )
    }

    /// P05b, three ticked.
    @Test func unplaced() async throws {
        let ids = try await save(7, video: 4)
        let model = UnplacedModel(library: library, places: .simulated)
        model.refresh()
        for item in model.items { await model.tiles.load(item.id) }
        assertScreenSnapshots(
            of: NavigationStack { UnplacedView(model: model, selection: Set(ids.suffix(3))) },
            variants: [SnapshotVariant(.iPhone, .light), SnapshotVariant(.iPhone, .dark), SnapshotVariant(.iPhone, .light, rightToLeft: true)]
        )
    }
}
