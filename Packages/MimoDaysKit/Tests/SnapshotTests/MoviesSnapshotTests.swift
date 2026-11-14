@testable import AppFeature
@testable import Core
import DesignSystem
import Foundation
import Persistence
import SwiftData
import SwiftUI
import Testing
import TestSupport

/// Movies: F01 library, F01e empty, the wizard's F02, F03 (end before start), F16, F04, F05. Today is Nov 11, 2026.
@MainActor
@Suite(.tags(.snapshot))
struct MoviesSnapshotTests {
    private let container = try! MimoDaysStore.makeContainer(inMemory: true)
    private let store: MediaStore
    private let defaults = UserDefaults(suiteName: "MoviesSnapshots-\(UUID().uuidString)")!
    /// The view's `.task` can still run after a test returns; its store must outlive the test.
    private static var stores: [ModelContainer] = []

    init() throws {
        store = try MediaStore(root: FileManager.default.temporaryDirectory.appending(path: "MoviesSnapshots-\(UUID().uuidString)"))
        Self.stores.append(container)
    }

    private var context: ModelContext { container.mainContext }
    private var library: MediaLibrary { MediaLibrary(context: context, store: store, thumbnails: ThumbnailPipeline()) }
    private var gmt: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }

    private func date(_ day: Int) -> Date {
        gmt.date(from: DateComponents(year: day / 10_000, month: day / 100 % 100, day: day % 100, hour: 12))!
    }

    /// Simulated-camera moments at noon UTC on these days; `video` indexes are 1 s videos.
    @discardableResult
    private func save(_ days: [Int], videos: Set<Int> = []) async throws -> [UUID] {
        let engine = SimulatedCaptureEngine()
        _ = await engine.start()
        let saver = MomentSaver(context: context, store: store, clock: TestDateProvider(), freeBytes: { nil })
        var ids: [UUID] = []
        for (index, day) in days.enumerated() {
            let media: CaptureResult.Media = videos.contains(index)
                ? .video(try await engine.record(limit: .seconds(1)))
                : .photo(try await engine.capturePhoto(flash: false, silent: true))
            let capture = CaptureResult(media: media, window: .init(), capturedAt: CaptureTime(instant: date(day), timeZone: .gmt))
            let draft = MomentDraft(
                capture: capture, caption: "",
                window: SelfieWindowFrame(frame: CGRect(x: 266.7, y: 111.1, width: 112, height: 150), preview: CGSize(width: 402, height: 536)),
                promptID: nil
            )
            ids.append(try await saver.save(draft).id)
        }
        return ids
    }

    private func wizard() -> NewMovieModel {
        NewMovieModel(library: library, clock: TestDateProvider(), calendar: { gmt }, seed: 1)
    }

    private func page(_ view: some View) -> some View {
        NavigationStack { view }.environment(AppRouter())
    }

    private let variants = [SnapshotVariant(.iPhone, .light), SnapshotVariant(.iPhone, .dark), SnapshotVariant(.iPhone, .light, .accessibilityExtraLarge)]

    /// F01 as drawn: October ready, two drafts, two movies.
    @Test func library() async throws {
        try await save((1...6).map { 20261000 + $0 * 3 })
        let summer = try await save([20260704, 20260815])
        let lena = try await save([20260312, 20260520])
        let september = try await save([20260905, 20260920])
        let year = try await save([20250214, 20250830])
        let now = TestDateProvider().now()
        let movies = MovieStore(context: context, store: store, now: { now })
        let rule = MovieSourceRule(kind: .selection)
        let a = try movies.create(title: "Summer 2026", source: rule, length: .short, aspectRatio: .portrait9x16, fit: .fill, momentIDs: summer)
        a.updatedAt = now.addingTimeInterval(-2 * 86_400)
        let b = try movies.create(title: "Lena's firsts", source: rule, length: .short, aspectRatio: .portrait9x16, fit: .fill, momentIDs: lena)
        b.updatedAt = date(20261002)
        for (title, ids, seconds, shape, made) in [
            ("September 2026", september, 62.0, MovieAspectRatio.portrait9x16, 20261001), ("2025, the whole year", year, 288.0, .landscape16x9, 20260103),
        ] {
            let project = try movies.create(title: title, source: rule, length: .short, aspectRatio: shape, fit: .fill, momentIDs: ids)
            let file = try store.store(Data(title.utf8), in: .derived, fileExtension: "mp4")
            try movies.attach(MovieRender(relativePath: file.relativePath, renderedAt: date(made), duration: seconds, resolution: .p1080, byteCount: file.byteCount), to: project)
        }
        let model = MoviesModel(library: library, clock: TestDateProvider(), calendar: { gmt }, defaults: defaults)
        model.refresh()
        for card in model.drafts + model.movies { if let id = card.coverID { await model.tiles.load(id) } }
        assertScreenSnapshots(of: page(MoviesView(model: model)), variants: variants)
    }

    /// F01e.
    @Test func empty() {
        let model = MoviesModel(library: library, clock: TestDateProvider(), calendar: { gmt }, defaults: defaults)
        model.refresh()
        assertScreenSnapshots(of: page(MoviesView(model: model)), variants: [SnapshotVariant(.iPhone, .light), SnapshotVariant(.iPhone, .dark)])
    }

    /// F02, Last month chosen.
    @Test func source() async throws {
        try await save([20261003, 20261010, 20260304, 20250506])
        let model = wizard()
        assertScreenSnapshots(of: page(SourceStep(model: model, path: .constant([]), close: {})), variants: variants)
    }

    /// F03 as drawn: from Jun 1, to May 3.
    @Test func datesEndBeforeStart() {
        let model = wizard()
        model.source = .dates
        model.from = 20260601
        model.to = 20260503
        assertScreenSnapshots(of: page(DatesStep(model: model, path: .constant([]))), variants: variants)
    }

    /// F16: last month has 3 moments.
    @Test func tooFew() async throws {
        try await save([20261003, 20261010, 20261020])
        let model = wizard()
        _ = model.loadCandidates()
        assertScreenSnapshots(of: page(SourceStep(model: model, path: .constant([]), close: {}, tooFew: true)), variants: variants)
    }

    /// F04: Quick, 9:16, Fill.
    @Test func length() async throws {
        try await save((1...30).map { 20261000 + $0 } + (1...34).map { 20261000 + ($0 % 28) + 1 })
        let model = wizard()
        _ = model.loadCandidates()
        assertScreenSnapshots(of: page(LengthStep(model: model, path: .constant([]))), variants: variants)
    }

    /// F05: the Quick pick of a busy October, two of them videos.
    @Test func moments() async throws {
        try await save((1...14).map { 20261000 + $0 * 2 }, videos: [2, 7])
        let model = wizard()
        _ = model.loadCandidates()
        model.length = .custom
        model.customMinutes = 1
        model.pickAutomatically()
        model.toggle(model.items[2].id)
        for item in model.items { await model.tiles.load(item.id) }
        assertScreenSnapshots(of: page(MomentsStep(model: model) {}), variants: variants)
    }
}
