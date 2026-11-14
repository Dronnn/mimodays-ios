@testable import AppFeature
@testable import Core
import Foundation
import Persistence
import SwiftData
import Testing
import TestSupport

/// 9.11 Delete (M15) and Recently deleted (M16/M16b): 30 days to change your mind, then gone with its files.
@MainActor
struct DeletionTests {
    private let container = try! MimoDaysStore.makeContainer(inMemory: true)
    private let store: MediaStore
    private static let day: TimeInterval = 86_400

    init() throws {
        store = try MediaStore(root: FileManager.default.temporaryDirectory.appending(path: "Deletion-\(UUID().uuidString)"))
    }

    private var context: ModelContext { container.mainContext }
    private var library: MediaLibrary { MediaLibrary(context: context, store: store, thumbnails: ThumbnailPipeline()) }

    private func deletion(at now: Date) -> DeletionStore { DeletionStore(context: context, store: store, now: { now }) }

    private func save() async throws -> UUID {
        let engine = SimulatedCaptureEngine()
        _ = await engine.start()
        let capture = CaptureResult(
            media: .photo(try await engine.capturePhoto(flash: false, silent: true)), window: .init(),
            capturedAt: CaptureTime(instant: .now, timeZone: .gmt)
        )
        let draft = MomentDraft(
            capture: capture, caption: "",
            window: SelfieWindowFrame(frame: CGRect(x: 266.7, y: 111.1, width: 112, height: 150), preview: CGSize(width: 402, height: 536)),
            promptID: nil
        )
        return try await MomentSaver(context: context, store: store, clock: TestDateProvider(), freeBytes: { nil }).save(draft).id
    }

    private func moment(_ id: UUID) throws -> Moment? {
        try context.fetch(FetchDescriptor<Moment>(predicate: #Predicate { $0.id == id })).first
    }

    @Test func deletingHidesItUntilItIsRecovered() async throws {
        let id = try await save()
        let now = Date(timeIntervalSince1970: 1_794_000_000)
        try deletion(at: now).moveToRecentlyDeleted([id])
        #expect(try moment(id)?.deletedAt == now)

        let memories = MemoriesModel(context: context, store: store, thumbnails: ThumbnailPipeline())
        memories.refresh()
        #expect(memories.days.isEmpty)
        let deleted = RecentlyDeletedModel(library: library, clock: TestDateProvider(now.addingTimeInterval(2 * Self.day)))
        deleted.refresh()
        #expect(deleted.items.map(\.id) == [id])
        #expect(deleted.daysLeft(deleted.items[0]) == 28)

        deleted.recover([id])
        deleted.refresh()
        memories.refresh()
        #expect(try deleted.items.isEmpty && moment(id)?.deletedAt == nil && memories.days.count == 1)
    }

    @Test func deletingForGoodTakesTheFilesAndTheCollectionLinks() async throws {
        let id = try await save()
        let collection = try #require(try CollectionStore(context: context).create("Walks", with: [id]))
        let paths = try #require(try moment(id)).media.map(\.relativePath)
        #expect(!paths.isEmpty && paths.allSatisfy { FileManager.default.fileExists(atPath: (try? store.url(for: $0).path()) ?? "") })

        try deletion(at: .now).deleteForever([id])
        #expect(try moment(id) == nil)
        #expect(try context.fetchCount(FetchDescriptor<CollectionMembership>()) == 0)
        #expect(try CollectionStore(context: context).collection(collection) != nil)
        #expect(paths.allSatisfy { !FileManager.default.fileExists(atPath: (try? store.url(for: $0).path()) ?? "") })
    }

    @Test func onlyMomentsPastThirtyDaysArePurged() async throws {
        let old = try await save()
        let recent = try await save()
        let kept = try await save()
        let now = Date(timeIntervalSince1970: 1_794_000_000)
        try deletion(at: now.addingTimeInterval(-31 * Self.day)).moveToRecentlyDeleted([old])
        try deletion(at: now.addingTimeInterval(-29 * Self.day)).moveToRecentlyDeleted([recent])
        try deletion(at: now).purgeExpired()
        #expect(try moment(old) == nil)
        #expect(try moment(recent)?.deletedAt != nil)
        #expect(try moment(kept)?.deletedAt == nil)
    }

    @Test(arguments: [(0.0, 30, 0), (0.5, 30, 0), (1.0, 29, 1), (12.2, 18, 12), (29.9, 1, 29), (31.0, 1, 31)])
    func daysLeftAndAgo(elapsed: Double, left: Int, ago: Int) {
        let deletedAt = Date(timeIntervalSince1970: 1_794_000_000)
        let now = deletedAt.addingTimeInterval(elapsed * Self.day)
        #expect(DeletionStore.daysLeft(deletedAt: deletedAt, now: now) == left)
        #expect(DeletionStore.daysAgo(deletedAt: deletedAt, now: now) == ago)
    }

    @Test func movieDraftsUsingTheMomentsAreCounted() async throws {
        let a = try await save()
        let b = try await save()
        let rule = MovieSourceRule(kind: .dateRange, start: .distantPast, end: .now)
        for title in ["November", "Walks"] {
            let project = MovieProject(title: title, sourceRule: rule, aspectRatio: .portrait9x16, length: .short)
            context.insert(project)
            context.insert(MovieClip(project: project, moment: try #require(try moment(a)), position: 0))
        }
        try context.save()
        let deletion = deletion(at: .now)
        #expect(try deletion.movieDrafts(using: [a]) == 2)
        #expect(try deletion.movieDrafts(using: [b]) == 0)
        try deletion.deleteForever([a])
        #expect(try context.fetchCount(FetchDescriptor<MovieProject>()) == 2)
        #expect(try context.fetchCount(FetchDescriptor<MovieClip>()) == 0)
    }

    @Test func theViewerMovesOnAfterADeleteAndEmptiesAtTheEnd() async throws {
        let a = try await save()
        let b = try await save()
        let c = try await save()
        let viewer = MomentViewerModel(pager: MomentPager(ids: [a, b, c], start: b), library: library)
        viewer.delete(b)
        #expect(viewer.ids == [a, c] && viewer.current == c)
        viewer.delete(c)
        #expect(viewer.ids == [a] && viewer.current == a)
        viewer.removeFromPager(a)
        #expect(viewer.ids.isEmpty && viewer.current == nil)
        #expect(try moment(b)?.deletedAt != nil && moment(c)?.deletedAt != nil && moment(a)?.deletedAt == nil)
    }

    @Test func editMomentDeletesIntoRecentlyDeleted() async throws {
        let id = try await save()
        let edit = try #require(EditMomentModel(id: id, library: library, voice: .simulated, places: .simulated))
        #expect(edit.movieDrafts == 0)
        #expect(edit.delete())
        #expect(try moment(id)?.deletedAt != nil)
    }
}
