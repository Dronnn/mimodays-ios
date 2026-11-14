@testable import AppFeature
@testable import Core
import DesignSystem
import Foundation
import Persistence
import SwiftData
import SwiftUI
import Testing
import TestSupport

/// Collections (M11 list, M11b new, M12 one collection), from moments saved off the simulated camera.
@MainActor
@Suite(.tags(.snapshot))
struct CollectionsSnapshotTests {
    private let container = try! MimoDaysStore.makeContainer(inMemory: true)
    private let store: MediaStore

    /// The view's `.task` can still run after a test returns; its store must outlive the test.
    private static var stores: [ModelContainer] = []

    init() throws {
        store = try MediaStore(root: FileManager.default.temporaryDirectory.appending(path: "CollectionsSnapshots-\(UUID().uuidString)"))
        Self.stores.append(container)
    }

    private var library: MediaLibrary { MediaLibrary(context: container.mainContext, store: store, thumbnails: ThumbnailPipeline()) }

    private func save(_ count: Int) async throws -> [UUID] {
        let engine = SimulatedCaptureEngine()
        _ = await engine.start()
        let saver = MomentSaver(context: container.mainContext, store: store, clock: TestDateProvider(), freeBytes: { nil })
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        var ids: [UUID] = []
        for index in 0..<count {
            let date = calendar.date(from: DateComponents(year: 2026, month: 3 + index % 9, day: 1 + index, hour: 12))!
            let capture = CaptureResult(
                media: .photo(try await engine.capturePhoto(flash: false, silent: true)), window: .init(),
                capturedAt: CaptureTime(instant: date, timeZone: .gmt)
            )
            let draft = MomentDraft(
                capture: capture, caption: "",
                window: SelfieWindowFrame(frame: CGRect(x: 266.7, y: 111.1, width: 112, height: 150), preview: CGSize(width: 402, height: 536)),
                promptID: nil
            )
            ids.append(try await saver.save(draft).id)
        }
        return ids
    }

    /// M11.
    @Test func list() async throws {
        let ids = try await save(6)
        // One moment in Recently deleted, so its row shows at the bottom as in M11.
        let deleted = try #require(try await save(1).first)
        try container.mainContext.fetch(FetchDescriptor<Moment>(predicate: #Predicate { $0.id == deleted })).first?.deletedAt = .now
        try container.mainContext.save()
        let collections = CollectionStore(context: container.mainContext)
        try collections.create("Walks", with: Array(ids.prefix(2)))
        try collections.create("Grandma", with: [ids[2]])
        try collections.create("Summer 2026", with: Array(ids[3...]))
        try collections.create("Lena's firsts", with: ids)
        let model = CollectionsModel(library: library)
        model.refresh()
        for collection in model.collections { await model.loadCover(collection) }
        assertScreenSnapshots(of: NavigationStack { CollectionsView(model: model) }, variants: [
            SnapshotVariant(.iPhone, .light), SnapshotVariant(.iPhone, .dark), SnapshotVariant(.iPhone, .light, .accessibilityExtraLarge),
            SnapshotVariant(.iPad, .light),
        ])
    }

    @Test func empty() {
        let model = CollectionsModel(library: library)
        model.refresh()
        assertScreenSnapshots(of: NavigationStack { CollectionsView(model: model) }, variants: [SnapshotVariant(.iPhone, .light), SnapshotVariant(.iPhone, .dark)])
    }

    /// M11b, on its own.
    @Test func new() {
        assertScreenSnapshots(
            of: NewCollectionSheet { _ in }.background(ColorToken.surfaceSheet.color.ignoresSafeArea()),
            variants: [SnapshotVariant(.iPhone, .light), SnapshotVariant(.iPhone, .dark), SnapshotVariant(.iPhone, .light, .accessibilityExtraLarge)]
        )
    }

    /// M12.
    @Test func detail() async throws {
        let ids = try await save(8)
        let id = try #require(try CollectionStore(context: container.mainContext).create("Lena's firsts", with: ids))
        let model = CollectionModel(id: id, library: library)
        model.refresh()
        await model.loadCover()
        for item in model.items { await model.load(item.id) }
        assertScreenSnapshots(of: NavigationStack { CollectionView(model: model) }, variants: [
            SnapshotVariant(.iPhone, .light), SnapshotVariant(.iPhone, .dark), SnapshotVariant(.iPhone, .light, .accessibilityExtraLarge),
            SnapshotVariant(.iPhone, .light, rightToLeft: true),
        ])
    }
}
