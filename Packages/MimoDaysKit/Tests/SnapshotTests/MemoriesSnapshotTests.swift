@testable import AppFeature
@testable import Core
import DesignSystem
import Foundation
import Persistence
import SwiftData
import SwiftUI
import Testing
import TestSupport

/// Memories (M01, M01e): real moments saved from the simulated camera, tiles decoded before the snapshot.
@MainActor
@Suite(.tags(.snapshot))
struct MemoriesSnapshotTests {
    private let container = try! MimoDaysStore.makeContainer(inMemory: true)
    private let store = try! MediaStore(root: FileManager.default.temporaryDirectory.appending(path: "MemoriesSnapshots-\(UUID().uuidString)"))
    private let clock = TestDateProvider()

    /// The view's `.task` can still run after a test returns; its store must outlive the test.
    private static var stores: [ModelContainer] = []

    init() {
        clock.set(Self.date(2026, 11, 11, 14, 40))
        Self.stores.append(container)
    }

    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }()

    private static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func save(at date: Date, place: String? = nil, caption: String = "") async throws -> UUID {
        let engine = SimulatedCaptureEngine()
        _ = await engine.start()
        let photo = try await engine.capturePhoto(flash: false, silent: true)
        let capture = CaptureResult(media: .photo(photo), window: .init(), capturedAt: CaptureTime(instant: date, timeZone: .gmt))
        let window = SelfieWindowFrame(frame: CGRect(x: 266.7, y: 111.1, width: 112, height: 150), preview: CGSize(width: 402, height: 536))
        let saver = MomentSaver(context: container.mainContext, store: store, clock: clock, freeBytes: { nil })
        return try await saver.save(MomentDraft(
            capture: capture, caption: caption, window: window, promptID: nil,
            place: place.map { ReviewPlace(label: $0, latitude: 40.18, longitude: 44.51, precision: .city, source: .gps) }
        )).id
    }

    private func memories() async -> MemoriesModel {
        let model = MemoriesModel(context: container.mainContext, store: store, thumbnails: ThumbnailPipeline(), clock: clock, calendar: { Self.utc })
        model.refresh()
        for case let .day(_, items) in model.rows {
            for item in items { await model.load(item.id) }
        }
        return model
    }

    private func screen(_ model: MemoriesModel) -> some View {
        NavigationStack { MemoriesView(model: model) }.environment(AppRouter())
    }

    @Test func empty() async {
        assertScreenSnapshots(of: screen(await memories()))
    }

    /// Today, Monday, Saturday, Thursday and October; one favourite; a few earlier months.
    private func populate() async throws {
        for (day, hours) in [(11, [14, 11, 8]), (9, [18, 9]), (7, [20, 16, 10]), (5, [12])] {
            for hour in hours { _ = try await save(at: Self.date(2026, 11, day, hour)) }
        }
        let favorite = try await save(at: Self.date(2026, 11, 9, 19))
        try container.mainContext.fetch(FetchDescriptor<Moment>(predicate: #Predicate { $0.id == favorite })).first?.isFavorite = true
        for (month, day) in [(10, 30), (10, 12), (9, 3), (6, 21), (3, 8)] {
            _ = try await save(at: Self.date(2026, month, day))
        }
    }

    /// M01.
    @Test func timeline() async throws {
        try await populate()
        assertScreenSnapshots(of: screen(await memories()))
    }

    /// M13: two moments ticked.
    @Test func select() async throws {
        try await populate()
        let model = await memories()
        let chosen = Set(model.allIDs.prefix(4).dropFirst(2))
        assertScreenSnapshots(of: NavigationStack { MemoriesView(model: model, selection: chosen) }.environment(AppRouter()), variants: [
            SnapshotVariant(.iPhone, .light), SnapshotVariant(.iPhone, .dark), SnapshotVariant(.iPhone, .light, .accessibilityExtraLarge),
            SnapshotVariant(.iPhone, .light, rightToLeft: true),
        ])
    }

    /// M02: November, today chosen.
    @Test func calendarMonth() async throws {
        try await populate()
        let model = await memories()
        model.mode = .calendar
        assertScreenSnapshots(of: screen(model), variants: [
            SnapshotVariant(.iPhone, .light), SnapshotVariant(.iPhone, .dark), SnapshotVariant(.iPhone, .light, .accessibilityExtraLarge),
            SnapshotVariant(.iPhone, .light, rightToLeft: true), SnapshotVariant(.iPad, .light),
        ])
    }

    /// M03: 2026 in dots.
    @Test func calendarYear() async throws {
        try await populate()
        let model = await memories()
        model.mode = .calendar
        model.show(year: 2026)
        assertScreenSnapshots(of: screen(model), variants: [SnapshotVariant(.iPhone, .light), SnapshotVariant(.iPhone, .dark), SnapshotVariant(.iPad, .light)])
    }

    /// M04: a day in two places, with a caption.
    @Test func day() async throws {
        _ = try await save(at: Self.date(2026, 11, 11, 8, 5), place: "Yerevan", caption: "Breakfast chaos, as usual")
        _ = try await save(at: Self.date(2026, 11, 11, 18, 42), place: "Dilijan")
        let model = await memories().dayModel(20261111)
        await model.refresh()
        assertScreenSnapshots(
            of: NavigationStack { DayView(model: model, thisYear: 2026) }.environment(AppRouter()),
            variants: [SnapshotVariant(.iPhone, .light), SnapshotVariant(.iPhone, .dark), SnapshotVariant(.iPhone, .light, .accessibilityExtraLarge)]
        )
    }

    /// M10: every favourite, newest first. Only one in `populate()`, so a few more get a heart.
    @Test func favorites() async throws {
        try await populate()
        for moment in try container.mainContext.fetch(FetchDescriptor<Moment>()).prefix(5) { moment.isFavorite = true }
        try container.mainContext.save()
        let model = await memories()
        for item in model.favorites { await model.load(item.id) }
        assertScreenSnapshots(
            of: NavigationStack { FavoritesView(model: model) }.environment(AppRouter()),
            variants: [SnapshotVariant(.iPhone, .light), SnapshotVariant(.iPhone, .dark), SnapshotVariant(.iPhone, .light, .accessibilityExtraLarge), SnapshotVariant(.iPad, .light)]
        )
    }

    /// M10e.
    @Test func favoritesEmpty() async throws {
        _ = try await save(at: Self.date(2026, 11, 11))
        let model = await memories()
        assertScreenSnapshots(
            of: NavigationStack { FavoritesView(model: model) }.environment(AppRouter()),
            variants: [SnapshotVariant(.iPhone, .light), SnapshotVariant(.iPhone, .dark)]
        )
    }

    /// Tile badges: favourite, a video's length, a voice note, all three.
    @Test func tiles() {
        func item(_ favorite: Bool, _ video: Bool) -> MemoryItem {
            MemoryItem(
                id: UUID(), localDay: 20261111, capturedAt: Self.date(2026, 11, 11), timeZoneID: "UTC",
                mediaType: video ? .video : .photo, origin: .manual, isFavorite: favorite
            )
        }
        let tiles: [(MemoryItem, TileDetail)] = [
            (item(false, false), TileDetail(hasVoiceNote: false)),
            (item(true, false), TileDetail(hasVoiceNote: false)),
            (item(false, true), TileDetail(duration: 10, hasVoiceNote: false)),
            (item(false, false), TileDetail(hasVoiceNote: true)),
            (item(true, true), TileDetail(duration: 75, hasVoiceNote: true)),
        ]
        let view = LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 4)], spacing: 4) {
            ForEach(tiles, id: \.0.id) { MemoryTile(item: $0.0, detail: $0.1, image: nil) }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(ColorToken.canvas.color)
        assertScreenSnapshots(of: view, variants: [SnapshotVariant(.iPhone, .light), SnapshotVariant(.iPhone, .dark), SnapshotVariant(.iPhone, .light, .accessibilityExtraLarge)])
    }
}
