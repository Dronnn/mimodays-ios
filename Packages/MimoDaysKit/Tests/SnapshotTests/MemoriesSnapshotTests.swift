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

    private static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func save(at date: Date) async throws -> UUID {
        let engine = SimulatedCaptureEngine()
        _ = await engine.start()
        let photo = try await engine.capturePhoto(flash: false, silent: true)
        let capture = CaptureResult(media: .photo(photo), window: .init(), capturedAt: CaptureTime(instant: date, timeZone: .gmt))
        let window = SelfieWindowFrame(frame: CGRect(x: 266.7, y: 111.1, width: 112, height: 150), preview: CGSize(width: 402, height: 536))
        let saver = MomentSaver(context: container.mainContext, store: store, clock: clock, freeBytes: { nil })
        return try await saver.save(MomentDraft(capture: capture, caption: "", window: window, promptID: nil, place: nil)).id
    }

    private func memories() async -> MemoriesModel {
        let model = MemoriesModel(context: container.mainContext, store: store, thumbnails: ThumbnailPipeline(), clock: clock)
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

    /// M01: today, Monday, Saturday and October; one favourite.
    @Test func timeline() async throws {
        for (day, hours) in [(11, [14, 11, 8]), (9, [18, 9]), (7, [20, 16, 10]), (5, [12])] {
            for hour in hours { _ = try await save(at: Self.date(2026, 11, day, hour)) }
        }
        let favorite = try await save(at: Self.date(2026, 11, 9, 19))
        try container.mainContext.fetch(FetchDescriptor<Moment>(predicate: #Predicate { $0.id == favorite })).first?.isFavorite = true
        _ = try await save(at: Self.date(2026, 10, 30))
        assertScreenSnapshots(of: screen(await memories()))
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
