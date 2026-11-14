@testable import AppFeature
@testable import Core
import Foundation
import Persistence
import SwiftData
import Testing
import TestSupport

/// 11.1 A movie project is its edit decisions; a rendered file is made from it and can go without the project going.
@MainActor
struct MovieStoreTests {
    private let container = try! MimoDaysStore.makeContainer(inMemory: true)
    private let store: MediaStore
    private let now = Date(timeIntervalSince1970: 1_794_000_000)

    init() throws {
        store = try MediaStore(root: FileManager.default.temporaryDirectory.appending(path: "MovieStore-\(UUID().uuidString)"))
    }

    private var context: ModelContext { container.mainContext }
    private var movies: MovieStore { MovieStore(context: context, store: store, now: { now }) }
    private let rule = MovieSourceRule(kind: .dateRange, start: .distantPast, end: .distantFuture)

    private func save(_ count: Int) async throws -> [UUID] {
        let engine = SimulatedCaptureEngine()
        _ = await engine.start()
        let saver = MomentSaver(context: context, store: store, clock: TestDateProvider(), freeBytes: { nil })
        var ids: [UUID] = []
        for _ in 0..<count {
            let capture = CaptureResult(
                media: .photo(try await engine.capturePhoto(flash: false, silent: true)), window: .init(),
                capturedAt: CaptureTime(instant: now, timeZone: .gmt)
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

    private func render(_ name: String) throws -> MovieRender {
        let file = try store.store(Data(name.utf8), in: .derived, fileExtension: "mp4")
        return MovieRender(relativePath: file.relativePath, renderedAt: now, duration: 62, resolution: .p1080, byteCount: file.byteCount)
    }

    @Test func aNewProjectKeepsTheMomentsInOrderWithTheDesignDefaults() async throws {
        let ids = try await save(3)
        let project = try movies.create(
            title: "October 2026", source: rule, length: .quick, aspectRatio: .landscape16x9, fit: .showAll, momentIDs: ids.reversed(), seed: 7
        )
        #expect(project.orderedClips.compactMap(\.moment?.id) == ids.reversed())
        #expect(project.fit == .showAll)
        #expect(project.selectionSeed == 7)
        #expect(project.status == .draft)
        #expect(project.render == nil)
        // F07-F09 as drawn: selfie where recorded, cut, dates and places on, clip sound at 70%, voice notes in.
        #expect(project.showsDates && project.showsPlaces)
        #expect(project.clipSoundLevel == 0.7)
        #expect(project.orderedClips.allSatisfy { $0.selfiePlacement == nil && $0.transition == .cut && $0.includesVoiceNote })
        #expect(try movies.drafts().map(\.id) == [project.id])
        #expect(try movies.movies().isEmpty)
    }

    @Test func aRenderedProjectIsAMovieAndANewRenderReplacesTheOldFile() async throws {
        let project = try movies.create(title: "September", source: rule, length: .short, aspectRatio: .portrait9x16, fit: .fill, momentIDs: try await save(2))
        let first = try render("first")
        try movies.attach(first, to: project)
        #expect(try movies.movies().map(\.id) == [project.id])
        #expect(try movies.drafts().isEmpty)
        #expect(project.status == .rendered)

        let second = try render("second")
        try movies.attach(second, to: project)
        #expect(project.render == second)
        #expect(!store.fileExists(first.relativePath))
        #expect(store.fileExists(second.relativePath))
    }

    @Test func losingTheRenderedFileLeavesTheProjectAsADraft() async throws {
        let ids = try await save(2)
        let project = try movies.create(title: "September", source: rule, length: .short, aspectRatio: .portrait9x16, fit: .fill, momentIDs: ids)
        let file = try render("movie")
        try movies.attach(file, to: project)
        try store.remove(file.relativePath)

        try movies.forgetMissingRenders()
        #expect(try movies.drafts().map(\.id) == [project.id])
        #expect(project.status == .draft)
        #expect(project.orderedClips.compactMap(\.moment?.id) == ids)
    }

    @Test func duplicateCopiesTheEditsButNotTheRender() async throws {
        let project = try movies.create(title: "Summer 2026", source: rule, length: .custom, aspectRatio: .square1x1, fit: .fill, momentIDs: try await save(2))
        project.customLength = 90
        project.showsPlaces = false
        project.orderedClips[0].transition = .fade
        project.orderedClips[1].selfiePlacement = .hidden
        project.orderedClips[1].trimStart = 0.5
        try movies.attach(try render("movie"), to: project)

        let copy = try movies.duplicate(project)
        #expect(copy.id != project.id)
        #expect(copy.title == "Summer 2026 copy")
        #expect(copy.render == nil)
        #expect(copy.customLength == 90 && !copy.showsPlaces && copy.aspectRatio == .square1x1)
        #expect(copy.orderedClips.map(\.transition) == [.fade, .cut])
        #expect(copy.orderedClips[1].selfiePlacement == .hidden)
        #expect(copy.orderedClips[1].trimStart == 0.5)
        #expect(copy.orderedClips.compactMap(\.moment?.id) == project.orderedClips.compactMap(\.moment?.id))
    }

    @Test func renameIgnoresBlankTitles() async throws {
        let project = try movies.create(title: "October", source: rule, length: .quick, aspectRatio: .portrait9x16, fit: .fill, momentIDs: [])
        try movies.rename(project, to: "  ")
        #expect(project.title == "October")
        try movies.rename(project, to: " Lena's firsts ")
        #expect(project.title == "Lena's firsts")
    }

    @Test func deletingAProjectTakesItsRenderButNeverItsMoments() async throws {
        let ids = try await save(2)
        let project = try movies.create(title: "September", source: rule, length: .short, aspectRatio: .portrait9x16, fit: .fill, momentIDs: ids)
        let file = try render("movie")
        try movies.attach(file, to: project)
        let music = try store.store(Data("music".utf8), in: .originals, fileExtension: "m4a")
        let track = MovieAudioTrack(kind: .soundtrack, relativePath: music.relativePath)
        track.project = project
        context.insert(track)
        let copy = try movies.duplicate(project)

        try movies.delete(project)
        #expect(!store.fileExists(file.relativePath))
        #expect(store.fileExists(music.relativePath), "the copy still uses the music")
        #expect(try context.fetchCount(FetchDescriptor<Moment>()) == 2)

        try movies.delete(copy)
        #expect(!store.fileExists(music.relativePath))
        #expect(try context.fetchCount(FetchDescriptor<MovieProject>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<MovieClip>()) == 0)
    }

    @Test func momentsDeletedSinceAreSkipped() async throws {
        let ids = try await save(3)
        let project = try movies.create(title: "October", source: rule, length: .quick, aspectRatio: .portrait9x16, fit: .fill, momentIDs: ids)
        try DeletionStore(context: context, store: store, now: { now }).moveToRecentlyDeleted([ids[1]])
        #expect(MovieStore.liveClips(of: project).compactMap(\.moment?.id) == [ids[0], ids[2]])
        try DeletionStore(context: context, store: store, now: { now }).deleteForever([ids[1]])
        #expect(project.orderedClips.count == 2)
    }
}
