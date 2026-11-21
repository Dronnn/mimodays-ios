@testable import AppFeature
import Core
import Foundation
import Persistence
import SwiftData
import Testing
import TestSupport

/// P8.3: hiding a moment or a whole day from memories.
@MainActor
struct MemoryVisibilityTests {
    private let container = try! TestStore.container()
    private var context: ModelContext { container.mainContext }

    /// 2026-11-11 23:00 in New York is 2026-11-12 04:00 UTC and 08:00 in Tbilisi.
    private static let lateInNewYork = Date(timeIntervalSince1970: 1_794_456_000)

    @discardableResult
    private func insert(_ instant: Date, zone: String) -> Moment {
        let moment = Moment(
            captured: CaptureTime(instant: instant, timeZone: TimeZone(identifier: zone)!), origin: .manual, mediaType: .photo, createdAt: .now
        )
        context.insert(moment)
        return moment
    }

    private func hiddenDays() throws -> [Int] {
        try context.fetch(FetchDescriptor<HiddenDay>()).map(\.localDay).sorted()
    }

    @Test func aMomentAddedToAHiddenDayIsHiddenWithIt() throws {
        try MemoryVisibility.setDayHidden(true, 2026_11_11, in: context)
        let later = insert(Self.lateInNewYork, zone: "America/New_York")
        let visibility = MemoryVisibility(context: context)
        #expect(visibility.isHidden(later) && visibility.isHiddenWithItsDay(later))
        #expect(!later.isHiddenFromMemories)
    }

    @Test func showingADayKeepsMomentsHiddenOnTheirOwn() throws {
        let moment = insert(Self.lateInNewYork, zone: "America/New_York")
        try MemoryVisibility.setHidden(true, moment, in: context)
        try MemoryVisibility.setDayHidden(true, 2026_11_11, in: context)
        try MemoryVisibility.setDayHidden(true, 2026_11_11, in: context)
        #expect(try hiddenDays() == [2026_11_11])
        try MemoryVisibility.setDayHidden(false, 2026_11_11, in: context)
        let visibility = MemoryVisibility(context: context)
        #expect(try hiddenDays().isEmpty)
        #expect(visibility.isHidden(moment) && !visibility.isHiddenWithItsDay(moment))
    }

    /// Relabelling days moves a hidden day with its moments, to every day they now fall on.
    @Test func aHiddenDayMovesWithItsMomentsWhenDaysAreRelabelled() throws {
        let late = insert(Self.lateInNewYork, zone: "America/New_York")
        let early = insert(Self.lateInNewYork.addingTimeInterval(-12 * 3600), zone: "America/New_York")
        try context.save()
        #expect(late.localDay == 2026_11_11 && early.localDay == 2026_11_11)
        try MemoryVisibility.setDayHidden(true, 2026_11_11, in: context)
        try MemoryVisibility.setDayHidden(true, 2025_01_01, in: context)
        let tbilisi = try #require(TimeZone(identifier: "Asia/Tbilisi"))
        #expect(try MomentDays.relabel(context, days: .thisIPhone, deviceZone: tbilisi) == 1)
        // The day split: 2026-11-11 keeps one moment, 2026-11-12 got the other; both stay hidden.
        // A rule no moment was on stays.
        #expect(try hiddenDays() == [2025_01_01, 2026_11_11, 2026_11_12])
        let visibility = MemoryVisibility(context: context)
        #expect(visibility.isHidden(late) && visibility.isHidden(early))
    }

    @Test func aHiddenDayWhoseMomentsAllMovedGoesWithThem() throws {
        let late = insert(Self.lateInNewYork, zone: "America/New_York")
        try context.save()
        try MemoryVisibility.setDayHidden(true, 2026_11_11, in: context)
        let tbilisi = try #require(TimeZone(identifier: "Asia/Tbilisi"))
        #expect(try MomentDays.relabel(context, days: .thisIPhone, deviceZone: tbilisi) == 1)
        #expect(try hiddenDays() == [2026_11_12])
        #expect(MemoryVisibility(context: context).isHidden(late))
    }
}
