@testable import AppFeature
@testable import Core
import Foundation
import Persistence
import SwiftData
import Testing
import TestSupport

/// 9.8 Collections (M11/M12): a collection only groups moments; nothing done to it ever deletes one.
@MainActor
struct CollectionTests {
    private let container = try! MimoDaysStore.makeContainer(inMemory: true)
    private let store: MediaStore

    init() throws {
        store = try MediaStore(root: FileManager.default.temporaryDirectory.appending(path: "Collections-\(UUID().uuidString)"))
    }

    private var context: ModelContext { container.mainContext }
    private var collections: CollectionStore { CollectionStore(context: context) }
    private var library: MediaLibrary { MediaLibrary(context: context, store: store, thumbnails: ThumbnailPipeline()) }

    private static func date(_ month: Int, _ day: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: 12))!
    }

    private func save(at date: Date) async throws -> UUID {
        let engine = SimulatedCaptureEngine()
        _ = await engine.start()
        let capture = CaptureResult(
            media: .photo(try await engine.capturePhoto(flash: false, silent: true)), window: .init(),
            capturedAt: CaptureTime(instant: date, timeZone: .gmt)
        )
        let draft = MomentDraft(
            capture: capture, caption: "",
            window: SelfieWindowFrame(frame: CGRect(x: 266.7, y: 111.1, width: 112, height: 150), preview: CGSize(width: 402, height: 536)),
            promptID: nil
        )
        return try await MomentSaver(context: context, store: store, clock: TestDateProvider(), freeBytes: { nil }).save(draft).id
    }

    private func count<T: PersistentModel>(_: T.Type) throws -> Int { try context.fetchCount(FetchDescriptor<T>()) }

    @Test func aNewCollectionIsNamedAndGoesFirst() throws {
        #expect(try collections.create("   ") == nil)
        let walks = try #require(try collections.create("Walks"))
        let firsts = try #require(try collections.create("  Lena's firsts "))
        let model = CollectionsModel(library: library)
        model.refresh()
        #expect(model.collections.map(\.id) == [firsts, walks])
        #expect(model.collections.first?.title == "Lena's firsts")
    }

    @Test func addingKeepsOrderAndSkipsMomentsAlreadyIn() async throws {
        let a = try await save(at: Self.date(3, 1))
        let b = try await save(at: Self.date(4, 1))
        let id = try #require(try collections.create("Firsts", with: [b]))
        try collections.add([a, b], to: id)
        let collection = try #require(try collections.collection(id))
        #expect(collection.orderedMoments.map(\.id) == [b, a])
        #expect(try count(CollectionMembership.self) == 2)
    }

    @Test func removingAMomentOrDeletingTheCollectionKeepsEveryMoment() async throws {
        let a = try await save(at: Self.date(3, 1))
        let b = try await save(at: Self.date(4, 1))
        let id = try #require(try collections.create("Firsts", with: [a, b]))
        try collections.remove([a], from: id)
        #expect(try count(Moment.self) == 2 && count(CollectionMembership.self) == 1)
        try collections.delete(id)
        #expect(try count(Moment.self) == 2 && count(CollectionMembership.self) == 0 && count(MomentCollection.self) == 0)
    }

    @Test func aMomentGoneForGoodLeavesTheCollection() async throws {
        let a = try await save(at: Self.date(3, 1))
        let b = try await save(at: Self.date(4, 1))
        let id = try #require(try collections.create("Firsts", with: [a, b]))
        try context.fetch(FetchDescriptor<Moment>(predicate: #Predicate { $0.id == a })).forEach(context.delete)
        try context.save()
        #expect(try collections.collection(id)?.orderedMoments.map(\.id) == [b])
        #expect(try count(MomentCollection.self) == 1)
    }

    @Test func recentlyDeletedMomentsDontCountOrCover() async throws {
        let older = try await save(at: Self.date(3, 1))
        let newer = try await save(at: Self.date(11, 1))
        let id = try #require(try collections.create("Firsts", with: [older, newer]))
        let model = CollectionsModel(library: library)
        model.refresh()
        let newerThumbnail = try context.fetch(FetchDescriptor<Moment>(predicate: #Predicate { $0.id == newer })).first?
            .media.first { $0.role == .thumbnail }?.relativePath
        #expect(model.collections.first?.count == 2 && model.collections.first?.coverPath == newerThumbnail)
        try context.fetch(FetchDescriptor<Moment>(predicate: #Predicate { $0.id == newer })).first?.deletedAt = .now
        try context.save()
        model.refresh()
        #expect(model.collections.first?.count == 1 && model.collections.first?.coverPath != newerThumbnail)

        let detail = CollectionModel(id: id, library: library)
        detail.refresh()
        #expect(detail.items.map(\.id) == [older])
    }

    @Test func aCollectionReadsOldestFirstWithItsSpan() async throws {
        let late = try await save(at: Self.date(11, 2))
        let early = try await save(at: Self.date(3, 14))
        let id = try #require(try collections.create("Firsts", with: [late, early]))
        let model = CollectionModel(id: id, library: library)
        model.refresh()
        #expect(model.items.map(\.id) == [early, late])
        #expect(model.span?.first == 20260314 && model.span?.last == 20261102)
        model.rename("  Lena's firsts ")
        model.refresh()
        #expect(model.title == "Lena's firsts")
        model.delete()
        #expect(!model.exists)
        model.refresh()
        #expect(!model.exists && (try? count(Moment.self)) == 2)
    }

    @Test func editMomentPutsItInExactlyTheChosenCollections() async throws {
        let id = try await save(at: Self.date(3, 1))
        let walks = try #require(try collections.create("Walks", with: [id]))
        let firsts = try #require(try collections.create("Firsts"))
        let edit = try #require(EditMomentModel(id: id, library: library, voice: .simulated, places: .simulated))
        #expect(edit.collectionIDs == [walks] && !edit.hasChanges)
        edit.collectionIDs = [firsts]
        #expect(edit.hasChanges)
        try await edit.save()
        #expect(try collections.collectionIDs(of: id) == [firsts])
        #expect(try count(CollectionMembership.self) == 1 && count(MomentCollection.self) == 2)
    }
}
