@testable import AppFeature
@testable import Core
import Foundation
import Persistence
import SwiftData
import Testing
import TestSupport

/// P8.4: a moment's own words to find it by.
@MainActor
struct TagsTests {
    @Test func aTagIsTrimmedAndAtMostThirtyCharacters() {
        #expect(Tags.cleaned("  first snow \n") == "first snow")
        #expect(Tags.cleaned("   ") == nil)
        let long = String(repeating: "é", count: 40)
        #expect(Tags.cleaned(long)?.count == 30)
        // User-perceived characters: a flag is one.
        #expect(Tags.cleaned(String(repeating: "🇦🇲", count: 31))?.count == 30)
    }

    /// Case and accents don't make another tag; the first spelling and the order stay.
    @Test func addingKeepsSpellingAndOrderAndSkipsDuplicates() {
        var tags = Tags.adding("Café", to: [])
        tags = Tags.adding(" Lena ", to: tags)
        #expect(tags == ["Café", "Lena"])
        #expect(Tags.problem(adding: "cafe", to: tags) == .duplicate)
        #expect(Tags.adding("CAFE", to: tags) == tags)
        #expect(Tags.problem(adding: "  ", to: tags) == .blank)
        #expect(Tags.problem(adding: "bike", to: tags) == nil)
    }

    @Test func atMostTenTags() {
        let ten = (1...10).map { "t\($0)" }
        #expect(Tags.problem(adding: "eleven", to: ten) == .full)
        #expect(Tags.adding("eleven", to: ten) == ten)
        #expect(Tags.problem(adding: "eleven", to: Array(ten.dropLast())) == nil)
    }

    /// Existing tags that match, most recent first, not ones the moment has.
    @Test func suggestionsAreRecentMatchingAndNew() {
        let recent = ["Lena", "lake", "Café", "Leo"]
        #expect(Tags.suggestions("le", from: recent, excluding: ["Leo"]) == ["Lena"])
        #expect(Tags.suggestions("", from: recent, excluding: ["cafe"]) == ["Lena", "lake", "Leo"])
    }

    /// Every tag in the archive once, from the most recent moment; deleted moments don't count.
    @Test func recentTagsComeFromTheArchive() throws {
        let container = try TestStore.container()
        let context = container.mainContext
        for (day, tags, deleted) in [(1, ["lake", "Lena"], false), (2, ["lena", "bike"], false), (3, ["secret"], true)] {
            let instant = Date(timeIntervalSince1970: 1_700_000_000 + Double(day) * 86_400)
            let moment = Moment(captured: CaptureTime(instant: instant, timeZoneID: "UTC"), origin: .manual, mediaType: .photo, createdAt: instant)
            moment.tags = tags
            if deleted { moment.deletedAt = instant }
            context.insert(moment)
        }
        try context.save()
        #expect(Tags.recent(in: context) == ["lena", "bike", "lake"])
    }
}
