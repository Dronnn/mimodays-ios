@testable import AppFeature
@testable import Core
import Foundation
import Persistence
import SwiftData
import Testing
import TestSupport

/// P8.8: a moment captured again on purpose, linked to the first and shown side by side.
@MainActor
struct ThenNowTests {
    private let container = try! TestStore.container()
    private var context: ModelContext { container.mainContext }

    @discardableResult
    private func moment(_ day: Int, repeatOf: UUID? = nil, deleted: Bool = false) -> Moment {
        let instant = Date(timeIntervalSince1970: 1_700_000_000 + Double(day) * 86_400)
        let moment = Moment(captured: CaptureTime(instant: instant, timeZoneID: "UTC"), origin: .manual, mediaType: .photo, createdAt: instant)
        moment.repeatOfMomentID = repeatOf
        if deleted { moment.deletedAt = instant }
        context.insert(moment)
        try! context.save()
        return moment
    }

    @Test func theSourceIsTheMomentCapturedAgain() {
        let then = moment(0)
        #expect(ThenNow.source(for: then.id, in: context) == then.id)
    }

    /// A repeat of a repeat links to the first, while it's there.
    @Test func aRepeatOfARepeatLinksToTheFirst() {
        let first = moment(0)
        let second = moment(10, repeatOf: first.id)
        #expect(ThenNow.source(for: second.id, in: context) == first.id)
        first.deletedAt = .now
        #expect(ThenNow.source(for: second.id, in: context) == second.id)
    }

    /// Gone (or in Recently Deleted) before the save: the moment saves unlinked.
    @Test func aGoneSourceLinksNothing() {
        let deleted = moment(0, deleted: true)
        #expect(ThenNow.source(for: deleted.id, in: context) == nil)
        #expect(ThenNow.source(for: UUID(), in: context) == nil)
        #expect(ThenNow.source(for: nil, in: context) == nil)
    }

    /// From either card: the newest repeat with its source, and every repeat to choose from, newest first.
    @Test func theComparisonShowsTheNewestRepeat() throws {
        let then = moment(0)
        let older = moment(10, repeatOf: then.id)
        let newer = moment(20, repeatOf: then.id)
        moment(30, repeatOf: then.id, deleted: true)
        let fromThen = try #require(ThenNow.comparison(for: then, in: context))
        #expect(fromThen.then?.id == then.id && fromThen.thenID == then.id)
        #expect(fromThen.repeats.map(\.id) == [newer.id, older.id])
        #expect(fromThen.selected == newer.id)
        let fromOlder = try #require(ThenNow.comparison(for: older, in: context))
        #expect(fromOlder.then?.id == then.id)
        #expect(fromOlder.selected == older.id)
        #expect(ThenNow.comparison(for: moment(40), in: context) == nil)
    }

    /// The first is in Recently Deleted: the repeat still opens it, with "This moment is unavailable" for Then.
    @Test func aDeletedSideIsLeftOut() throws {
        let then = moment(0)
        let now = moment(10, repeatOf: then.id)
        then.deletedAt = .now
        let comparison = try #require(ThenNow.comparison(for: now, in: context))
        #expect(comparison.then == nil && comparison.thenID == then.id)
        #expect(comparison.repeats.map(\.id) == [now.id])
    }

    /// Deleted for good: the repeat stays, unlinked.
    @Test func deletingTheFirstForGoodUnlinksItsRepeats() throws {
        let store = try MediaStore(root: FileManager.default.temporaryDirectory.appending(path: "ThenNow-\(UUID().uuidString)"))
        let then = moment(0, deleted: true)
        let now = moment(10, repeatOf: then.id)
        try DeletionStore(context: context, store: store).deleteForever([then.id])
        #expect(now.repeatOfMomentID == nil)
        #expect(try context.fetchCount(FetchDescriptor<Moment>()) == 1)
    }
}
