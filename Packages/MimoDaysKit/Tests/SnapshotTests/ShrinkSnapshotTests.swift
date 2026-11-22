@testable import AppFeature
@testable import Core
import DesignSystem
import Foundation
import Persistence
import SwiftData
import SwiftUI
import Testing
import TestSupport

/// P3.5 Make videos smaller: X03's rows, X04, X04b and X05; P3.6 Move originals: X06.
@MainActor
@Suite(.tags(.snapshot), .serialized)
struct ShrinkSnapshotTests {
    /// Never finishes: X05 stays mid-run.
    struct HeldTranscoder: VideoTranscoding {
        func transcode(_ source: URL, to destination: URL, size: VideoSize) async throws {
            try await Task.sleep(for: .seconds(3_600))
        }
    }

    private let container = try! TestStore.container()
    private let store: MediaStore
    private let defaults: UserDefaults
    private static var containers: [ModelContainer] = []
    /// Wed, Nov 11 2026, noon UTC.
    private let now = Date(timeIntervalSince1970: 1_794_398_400)

    init() throws {
        store = try MediaStore(root: FileManager.default.temporaryDirectory.appending(path: "ShrinkSnapshots-\(UUID().uuidString)"))
        defaults = try #require(UserDefaults(suiteName: "ShrinkSnapshots-\(UUID().uuidString)"))
        Self.containers.append(container)
    }

    private var library: MediaLibrary { MediaLibrary(context: container.mainContext, store: store, thumbnails: ThumbnailPipeline()) }

    /// Video moments whose records say 1080p at 16 Mbit/s on both cameras, `seconds` long.
    @discardableResult
    private func videos(daysAgo: [Int], seconds: Double = 30) throws -> [Moment] {
        try daysAgo.map { days in
            let date = now.addingTimeInterval(TimeInterval(-days * 86_400))
            let moment = Moment(captured: CaptureTime(instant: date, timeZone: .gmt), origin: .manual, mediaType: .video, createdAt: date)
            container.mainContext.insert(moment)
            for role in [MediaRole.rearSource, .frontSource] {
                moment.media.append(MomentMedia(
                    role: role, relativePath: "originals/\(UUID().uuidString).mov", uniformType: "com.apple.quicktime-movie",
                    pixelWidth: 1080, pixelHeight: 1920, checksum: "c", byteCount: Int64(16_000_000 / 8 * seconds), duration: seconds
                ))
            }
            try container.mainContext.save()
            return moment
        }
    }

    private func page(_ view: some View, run: ShrinkRun) -> some View {
        NavigationStack { view.background(ColorToken.canvas.color.ignoresSafeArea()) }
            .environment(AppRouter())
            .environment(\.mediaLibrary, library)
            .environment(run)
    }

    private func run(transcoder: any VideoTranscoding = HeldTranscoder()) -> ShrinkRun {
        ShrinkRun(library: library, transcoder: transcoder, defaults: defaults, freeSpace: { nil })
    }

    private let variants = [SnapshotVariant(.iPhone, .light), SnapshotVariant(.iPhone, .dark), SnapshotVariant(.iPhone, .light, .accessibilityExtraLarge)]

    /// X03: what it would free, on Storage.
    @Test func storageRow() throws {
        try videos(daysAgo: Array(35..<60), seconds: 40)
        let model = StorageModel(library: library, temporaryDirectory: FileManager.default.temporaryDirectory.appending(path: "None-\(UUID().uuidString)"))
        assertScreenSnapshots(of: page(StorageView(model: model, openMovies: {}), run: run()), variants: variants)
    }

    /// X04: older than 30 days, Balanced.
    @Test func makeSmaller() throws {
        try videos(daysAgo: [2, 3] + Array(35..<60), seconds: 40)
        let model = ShrinkModel(library: library, now: { [now] in now })
        assertScreenSnapshots(of: page(ShrinkView(model: model, start: {}), run: run()), variants: variants)
    }

    /// X04 with nothing old enough.
    @Test func makeSmallerNothing() throws {
        try videos(daysAgo: [2, 3])
        let model = ShrinkModel(library: library, now: { [now] in now })
        assertScreenSnapshots(of: page(ShrinkView(model: model, start: {}), run: run()), variants: [SnapshotVariant(.iPhone, .light)])
    }

    /// X04b: three ticked, by day.
    @Test func chooseVideos() throws {
        let moments = try videos(daysAgo: [0, 0, 0, 2, 2, 4, 4, 4, 6, 6, 6])
        let model = ShrinkModel(library: library, now: { [now] in now })
        let chooser = ShrinkChooser(model: model, chosen: Set([moments[0].id, moments[1].id, moments[4].id])) { _ in }
        assertScreenSnapshots(of: page(chooser, run: run()), variants: variants)
    }

    /// X06: no folder yet, so Move waits for one.
    @Test func moveOriginals() throws {
        try videos(daysAgo: [2, 3] + Array(35..<60), seconds: 40)
        let model = ShrinkModel(library: library, moving: true, now: { [now] in now })
        let archive = OriginalArchive(indexURL: FileManager.default.temporaryDirectory.appending(path: "Index-\(UUID().uuidString).json"))
        assertScreenSnapshots(of: page(ShrinkView(model: model, archive: archive, start: {}), run: run()), variants: variants)
    }

    /// X06 with the folder picked.
    @Test func moveOriginalsToAFolder() throws {
        try videos(daysAgo: Array(35..<60), seconds: 40)
        let folder = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString)/Video archive")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let archive = OriginalArchive(indexURL: FileManager.default.temporaryDirectory.appending(path: "Index-\(UUID().uuidString).json"))
        try archive.setFolder(folder)
        let model = ShrinkModel(library: library, moving: true, now: { [now] in now })
        assertScreenSnapshots(of: page(ShrinkView(model: model, archive: archive, start: {}), run: run()), variants: [SnapshotVariant(.iPhone, .light)])
    }

    /// X05: 37 of 142 videos, mid-run.
    @Test func running() async throws {
        let moments = try videos(daysAgo: Array(35..<40))
        let job = ShrinkRun.Job(size: .balanced, remaining: moments.map(\.id) + (0..<100).map { _ in UUID() }, total: 142, done: 37, freed: 812_000_000)
        defaults.set(try JSONEncoder().encode(job), forKey: "shrinkJob")
        let run = run()
        run.resumeIfNeeded()
        defer { run.stop() }
        assertScreenSnapshots(of: page(ShrinkProgressView(run: run, done: {}), run: run), variants: variants)
    }

    /// X05 done: the last video was already gone, so the run ends at once.
    @Test func finished() async throws {
        let job = ShrinkRun.Job(size: .balanced, remaining: [UUID()], total: 142, done: 141, freed: 2_140_000_000)
        defaults.set(try JSONEncoder().encode(job), forKey: "shrinkJob")
        let run = run()
        run.resumeIfNeeded()
        for _ in 0..<100 where run.isRunning { try await Task.sleep(for: .milliseconds(10)) }
        assertScreenSnapshots(of: page(ShrinkProgressView(run: run, done: {}), run: run), variants: [SnapshotVariant(.iPhone, .light)])
    }
}
