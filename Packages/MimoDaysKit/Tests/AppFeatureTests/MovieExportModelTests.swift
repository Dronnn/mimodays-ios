@preconcurrency import AVFoundation
@testable import AppFeature
@testable import Core
import Foundation
import Persistence
import SwiftData
import Testing
import TestSupport

/// 11.11 F11-F14: the export renders the project to a file kept as its render, says only what F11 allows, and
/// stops before it starts when there's no room.
@MainActor
@Suite(.serialized)
struct MovieExportModelTests {
    private let container = try! TestStore.container()
    private let store: MediaStore
    private let clock = TestDateProvider(Date(timeIntervalSince1970: 1_794_398_400))

    init() throws {
        store = try MediaStore(root: FileManager.default.temporaryDirectory.appending(path: "MovieExport-\(UUID().uuidString)"))
    }

    private var context: ModelContext { container.mainContext }
    private var library: MediaLibrary { MediaLibrary(context: context, store: store, thumbnails: ThumbnailPipeline()) }
    private var movies: MovieStore { MovieStore(context: context, store: store, now: { [clock] in clock.now() }) }

    private func project(photos count: Int, located: Bool = false) async throws -> MovieProject {
        let engine = SimulatedCaptureEngine()
        _ = await engine.start()
        let saver = MomentSaver(context: context, store: store, clock: clock, freeBytes: { nil })
        var ids: [UUID] = []
        for _ in 0..<count {
            let capture = CaptureResult(
                media: .photo(try await engine.capturePhoto(flash: .off, silent: true)), window: .init(),
                capturedAt: CaptureTime(instant: clock.now(), timeZone: .gmt)
            )
            let draft = MomentDraft(
                capture: capture, caption: "",
                window: SelfieWindowFrame(frame: CGRect(x: 266.7, y: 111.1, width: 112, height: 150), preview: CGSize(width: 402, height: 536)),
                promptID: nil,
                place: located ? ReviewPlace(label: "Oakland", latitude: 37.8044, longitude: -122.2712, precision: .exact, source: .manual) : nil
            )
            ids.append(try await saver.save(draft).id)
        }
        return try movies.create(
            title: "October 2026", source: MovieSourceRule(kind: .selection, momentIDs: ids), length: .full,
            aspectRatio: .portrait9x16, fit: .fill, momentIDs: ids
        )
    }

    @Test func estimatesFollowTheDesign() async throws {
        let project = try await project(photos: 2)
        let model = MovieExportModel(project: project, library: library, clock: clock, freeSpace: { 12_000_000_000 })
        // 64 s at 1080p is "About 95 MB" on F11; 720p "about 45 MB" on F14.
        let perSecond1080 = MovieExportModel.bitrate(.p1080) / 8
        #expect(abs(perSecond1080 * 64 - 95_000_000) < 1_000_000)
        #expect(abs(MovieExportModel.bitrate(.p720) / 8 * 64 - 45_000_000) < 1_000_000)
        #expect(model.estimatedBytes(.p1080) == Int64(model.plan.duration * perSecond1080))
    }

    @Test func notEnoughRoomStopsBeforeRendering() async throws {
        let project = try await project(photos: 2)
        let model = MovieExportModel(project: project, library: library, clock: clock, freeSpace: { 1000 })
        model.start()
        guard case let .failed(.space(needed)) = model.phase else {
            Issue.record("Expected a space failure, got \(model.phase)")
            return
        }
        #expect(needed > 0)
        #expect(project.render == nil)
    }

    @Test func exportKeepsTheFileAsTheProjectsRenderWithoutItsPlace() async throws {
        let project = try await project(photos: 2, located: true)
        let model = MovieExportModel(project: project, library: library, clock: clock, freeSpace: { nil })
        model.resolution = .p720
        model.start()
        await model.waitForRender()
        guard case let .ready(render) = model.phase else {
            Issue.record("Expected ready, got \(model.phase)")
            return
        }
        #expect(project.render == render)
        #expect(project.status == .rendered)
        #expect(render.resolution == .p720)
        #expect(render.byteCount > 0)
        let asset = AVURLAsset(url: try store.url(for: render.relativePath))
        let duration = try await asset.load(.duration).seconds
        #expect(abs(duration - MovieSelection.photoSeconds * 2) < 0.1)
        let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
        let size = try await track.load(.naturalSize)
        #expect(size == CGSize(width: 720, height: 1280))
        let metadata = try await asset.load(.metadata)
        #expect(!metadata.contains { $0.identifier == .quickTimeMetadataLocationISO6709 || $0.identifier == .commonIdentifierLocation })
    }

    @Test func aNewExportReplacesTheOldFile() async throws {
        let project = try await project(photos: 2)
        let model = MovieExportModel(project: project, library: library, clock: clock, freeSpace: { nil })
        model.resolution = .p720
        model.start()
        await model.waitForRender()
        let first = try #require(project.render)
        model.start()
        await model.waitForRender()
        let second = try #require(project.render)
        #expect(first.relativePath != second.relativePath)
        #expect(!store.fileExists(first.relativePath))
        #expect(store.fileExists(second.relativePath))
    }

    /// Two Export taps before the options make way render once.
    @Test func aSecondStartWhileRenderingDoesNothing() async throws {
        let project = try await project(photos: 2)
        let model = MovieExportModel(project: project, library: library, clock: clock, freeSpace: { nil })
        model.resolution = .p720
        model.start()
        let first = try #require(model.task)
        model.start()
        #expect(model.task == first)
        model.cancel()
        await first.value
        #expect(project.render == nil)
    }

    /// Settings' quality is only where the movie starts; one made before keeps the quality it was made in.
    @Test func anEarlierRenderKeepsItsQuality() async throws {
        let project = try await project(photos: 2)
        var defaults = MovieDefaults()
        defaults.resolution = .p2160
        defaults.exactPlaceInFiles = true
        let first = MovieExportModel(project: project, library: library, defaults: defaults, clock: clock, freeSpace: { nil })
        #expect(first.resolution == .p2160 && first.placeInFile)
        first.resolution = .p720
        first.start()
        await first.waitForRender()
        let again = MovieExportModel(project: project, library: library, defaults: defaults, clock: clock, freeSpace: { nil })
        #expect(again.resolution == .p720 && again.placeInFile)
    }

    @Test func cancellingLeavesTheProjectAsItWas() async throws {
        let project = try await project(photos: 3)
        let model = MovieExportModel(project: project, library: library, clock: clock, freeSpace: { nil })
        model.start()
        model.cancel()
        await model.waitForRender()
        // JJ05: Export canceled, with Export again.
        #expect(model.phase == .canceled)
        #expect(project.render == nil)
    }

    /// Doc 01 §16: a moment whose picture is damaged is left out of the movie, as a deleted one is.
    @Test func aDamagedPictureIsLeftOut() async throws {
        let project = try await project(photos: 2)
        let moment = try #require(try context.fetch(FetchDescriptor<Moment>()).first)
        let main = try #require(MomentSummary(moment).mainPath)
        try Data("not a picture".utf8).write(to: try store.url(for: main))
        let model = MovieExportModel(project: project, library: library, clock: clock, freeSpace: { nil })
        model.resolution = .p720
        model.start()
        await model.waitForRender()
        guard case let .ready(render) = model.phase else {
            Issue.record("Expected ready, got \(model.phase)")
            return
        }
        #expect(abs(render.duration - MovieSelection.photoSeconds) < 0.1)
    }

    /// Doc 01 §16 "rendering failure": nothing left to show stops on F14, and the draft stays a draft.
    @Test func nothingReadableFailsAndKeepsTheDraft() async throws {
        let project = try await project(photos: 2)
        for media in try context.fetch(FetchDescriptor<MomentMedia>()) {
            try Data("not a picture".utf8).write(to: try store.url(for: media.relativePath))
        }
        let model = MovieExportModel(project: project, library: library, clock: clock, freeSpace: { nil })
        model.resolution = .p720
        model.start()
        await model.waitForRender()
        #expect(model.phase == .failed(.other))
        #expect(project.render == nil)
    }

    @Test func placeIsWrittenOnlyWhenAskedFor() {
        #expect(MovieExportModel.iso6709(latitude: 37.8044, longitude: -122.2712) == "+37.8044-122.2712/")
        #expect(MovieExportModel.iso6709(latitude: -3.5, longitude: 7.25) == "-03.5000+007.2500/")
    }

    // MARK: P8.13 continued export

    /// Takes or refuses exports; runs them when told to.
    @MainActor
    final class FakeContinuation: ContinuedExportScheduler {
        var isAvailable = true
        var accepts = true
        private(set) var titles: [String] = []
        private var waiting: [@MainActor (any ContinuedExportTask) -> Void] = []

        func submit(title: String, run: @escaping @MainActor (any ContinuedExportTask) -> Void) -> Bool {
            titles.append(title)
            guard accepts else { return false }
            waiting.append(run)
            return true
        }

        /// iOS's turn comes for the oldest waiting export.
        @discardableResult
        func runNext() -> FakeTask {
            let task = FakeTask()
            waiting.removeFirst()(task)
            return task
        }
    }

    @MainActor
    final class FakeTask: ContinuedExportTask {
        var stopped: (@MainActor () -> Void)?
        private(set) var reported: [Double] = []
        private(set) var result: Bool?
        func report(_ fraction: Double) { reported.append(fraction) }
        func finish(success: Bool) { if result == nil { result = success } }
    }

    /// Handed to iOS, it waits, then renders when its turn comes; the system sees progress and the end.
    @Test func iOSTakesTheExportOn() async throws {
        let project = try await project(photos: 2)
        let continuation = FakeContinuation()
        let model = MovieExportModel(project: project, library: library, clock: clock, freeSpace: { nil }, continuation: continuation)
        model.resolution = .p720
        #expect(model.canLeave)
        model.start()
        #expect(model.phase == .waiting && model.runsInBackground && !model.foregroundOnly)
        #expect(continuation.titles == ["Exporting a movie"])
        model.start()
        #expect(continuation.titles.count == 1)
        let task = continuation.runNext()
        await model.waitForRender()
        guard case .ready = model.phase else {
            Issue.record("Expected ready, got \(model.phase)")
            return
        }
        #expect(task.result == true)
        #expect(!task.reported.isEmpty && task.reported.allSatisfy { (0...1).contains($0) })
        #expect(project.render != nil)
    }

    /// iOS turns it down: the export runs as before, while MimoDays stays open.
    @Test func refusedRunsInTheForeground() async throws {
        let project = try await project(photos: 2)
        let continuation = FakeContinuation()
        continuation.accepts = false
        let model = MovieExportModel(project: project, library: library, clock: clock, freeSpace: { nil }, continuation: continuation)
        model.resolution = .p720
        model.start()
        #expect(model.foregroundOnly && !model.runsInBackground)
        await model.waitForRender()
        guard case .ready = model.phase else {
            Issue.record("Expected ready, got \(model.phase)")
            return
        }
        // Before iOS 26, or not set up: nothing is handed over and nothing is said about leaving.
        continuation.isAvailable = false
        let plain = MovieExportModel(project: project, library: library, clock: clock, freeSpace: { nil }, continuation: continuation)
        #expect(!plain.canLeave)
        #expect(MovieExportModel(project: project, library: library, clock: clock, freeSpace: { nil }).canLeave == false)
    }

    /// Cancel while it waits: when iOS's turn comes, nothing renders and iOS hears it's done.
    @Test func cancelledWhileWaiting() async throws {
        let project = try await project(photos: 2)
        let continuation = FakeContinuation()
        let model = MovieExportModel(project: project, library: library, clock: clock, freeSpace: { nil }, continuation: continuation)
        model.start()
        model.cancel()
        #expect(model.phase == .canceled)
        let task = continuation.runNext()
        #expect(task.result == false && model.phase == .canceled && model.task == nil)
        #expect(project.render == nil)
    }

    /// The system's Cancel (or iOS taking the time back) stops the render; the draft stays and Try again is offered.
    @Test func stoppedByIOSKeepsTheDraft() async throws {
        let project = try await project(photos: 4)
        let continuation = FakeContinuation()
        let model = MovieExportModel(project: project, library: library, clock: clock, freeSpace: { nil }, continuation: continuation)
        model.start()
        let task = continuation.runNext()
        task.stopped?()
        await model.waitForRender()
        // JJ05: Export stopped. Your draft is safe.
        #expect(model.phase == .stopped)
        #expect(task.result == false)
        #expect(project.render == nil)
        #expect(project.orderedClips.count == 4)
    }

    private func jobs() throws -> [ExportJob] {
        try context.fetch(FetchDescriptor<ExportJob>(sortBy: [SortDescriptor(\.createdAt)]))
    }

    /// Each export leaves one row: queued, running, then how it ended; a relaunch closes the ones cut short.
    @Test func eachExportIsRecorded() async throws {
        let project = try await project(photos: 2)
        let continuation = FakeContinuation()
        let model = MovieExportModel(project: project, library: library, clock: clock, freeSpace: { nil }, continuation: continuation)
        model.resolution = .p720
        model.start()
        #expect(try jobs().map(\.state) == [.queued])
        #expect(try jobs().first?.sourceIDs == [project.id] && jobs().first?.kind == .movie)
        continuation.runNext()
        #expect(try jobs().map(\.state) == [.running])
        await model.waitForRender()
        #expect(try jobs().map(\.state) == [.finished])
        model.start()
        model.cancel()
        #expect(try jobs().map(\.state) == [.finished, .cancelled])

        // Quit while one waited: the next launch says it stopped, and never that it finished.
        model.start()
        #expect(try jobs().last?.state == .queued)
        MovieExportModel.reconcileJobs(in: context, now: clock.now())
        #expect(try jobs().map(\.state) == [.finished, .cancelled, .failed])
        #expect(try jobs().last?.finishedAt != nil)
    }

    /// One export at a time: the same movie reopens its export; another one waits until it's done.
    @Test func oneExportAtATime() async throws {
        let first = try await project(photos: 2)
        let second = try await project(photos: 2)
        let continuation = FakeContinuation()
        let center = MovieExportCenter()
        let make = { (project: MovieProject) in
            { MovieExportModel(project: project, library: self.library, clock: self.clock, freeSpace: { nil }, continuation: continuation) }
        }
        let model = try #require(center.model(for: first, make: make(first)))
        model.start()
        #expect(center.isExporting)
        #expect(center.model(for: first, make: make(first)) === model)
        #expect(center.model(for: second, make: make(second)) == nil)
        model.cancel()
        #expect(!center.isExporting)
        let next = try #require(center.model(for: second, make: make(second)))
        #expect(next !== model && next.project.id == second.id)
    }

    /// JJ03: Movies shows the export under way and one that finished away from its screen, until that screen closes.
    @Test func moviesShowsTheExportUntilItsSeen() async throws {
        let project = try await project(photos: 2)
        let continuation = FakeContinuation()
        let center = MovieExportCenter(continuation: continuation)
        let model = try #require(center.model(for: project) {
            MovieExportModel(project: project, library: self.library, clock: self.clock, freeSpace: { nil }, continuation: center.continuation)
        })
        #expect(center.row == nil)
        model.resolution = .p720
        model.start()
        #expect(center.row === model)
        // Back to Movies: the screen closes, the export goes on.
        center.release(model)
        #expect(center.row === model)
        continuation.runNext()
        await model.waitForRender()
        #expect(center.row === model)
        // View export, then Done.
        center.release(model)
        #expect(center.row == nil && center.active == nil)
        // A cancel isn't kept.
        let again = try #require(center.model(for: project) {
            MovieExportModel(project: project, library: self.library, clock: self.clock, freeSpace: { nil }, continuation: continuation)
        })
        again.start()
        again.cancel()
        #expect(center.row == nil)
    }
}
