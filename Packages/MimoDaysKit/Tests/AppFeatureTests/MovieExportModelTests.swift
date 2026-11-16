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

    @Test func cancellingLeavesTheProjectAsItWas() async throws {
        let project = try await project(photos: 3)
        let model = MovieExportModel(project: project, library: library, clock: clock, freeSpace: { nil })
        model.start()
        model.cancel()
        await model.waitForRender()
        #expect(model.phase == .options)
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
}
