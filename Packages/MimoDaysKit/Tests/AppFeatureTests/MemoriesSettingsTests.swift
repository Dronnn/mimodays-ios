@testable import AppFeature
import Core
import Foundation
import Persistence
import SwiftData
import Testing
import TestSupport

/// 13.4 (S09): the Memories settings are kept, sort the timeline, and decide each moment's day.
@MainActor
struct MemoriesSettingsTests {
    private let container = try! MimoDaysStore.makeContainer(inMemory: true)
    private let store = try! MediaStore(root: FileManager.default.temporaryDirectory.appending(path: "MemoriesSettings-\(UUID().uuidString)"))

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

    @Test func settingsAreKeptAcrossLaunches() throws {
        let defaults = try #require(UserDefaults(suiteName: "MemoriesSettingsTests"))
        defaults.removePersistentDomain(forName: "MemoriesSettingsTests")
        let preferences = MemoriesPreferences(defaults: defaults)
        #expect(preferences.settings == MemoriesSettings())
        preferences.settings.opensIn = .calendar
        preferences.settings.newestFirst = false
        preferences.settings.onThisDayOnToday = false
        preferences.settings.days = .thisIPhone
        let relaunched = MemoriesPreferences(defaults: defaults).settings
        #expect(relaunched.opensIn == .calendar && !relaunched.newestFirst && !relaunched.onThisDayOnToday && relaunched.days == .thisIPhone)
    }

    @Test func settingsSavedByAnEarlierVersionKeepTheirValues() throws {
        let defaults = try #require(UserDefaults(suiteName: "MemoriesSettingsUpgradeTests"))
        defaults.removePersistentDomain(forName: "MemoriesSettingsUpgradeTests")
        defaults.set(Data(#"{"newestFirst":false}"#.utf8), forKey: "memoriesSettings")
        let settings = MemoriesPreferences(defaults: defaults).settings
        #expect(!settings.newestFirst)
        #expect(settings.opensIn == .timeline && settings.onThisDayOnToday && settings.days == .whereTaken)
    }

    @Test func daysFollowWhereTheMomentWasTakenOrThisIPhone() throws {
        let moment = insert(Self.lateInNewYork, zone: "America/New_York")
        #expect(moment.localDay == 2026_11_11)
        let tbilisi = try #require(TimeZone(identifier: "Asia/Tbilisi"))
        #expect(try MomentDays.relabel(context, days: .thisIPhone, deviceZone: tbilisi) == 1)
        #expect(moment.localDay == 2026_11_12)
        // Nothing moves twice.
        #expect(try MomentDays.relabel(context, days: .thisIPhone, deviceZone: tbilisi) == 0)
        #expect(try MomentDays.relabel(context, days: .whereTaken, deviceZone: tbilisi) == 1)
        #expect(moment.localDay == 2026_11_11)
    }

    @Test func oldestFirstPutsTheOldestMonthAndMomentOnTop() throws {
        insert(Date(timeIntervalSince1970: 1_791_374_400), zone: "UTC") // 2026-10-07 12:00
        insert(Self.lateInNewYork, zone: "America/New_York")
        insert(Self.lateInNewYork.addingTimeInterval(-3600), zone: "America/New_York")
        try context.save()
        let model = MemoriesModel(context: context, store: store, thumbnails: ThumbnailPipeline())
        model.newestFirst = false
        model.refresh()
        #expect(model.rows.map(\.id) == [2026_10, 2026_10_07, 2026_11, 2026_11_11])
        guard case let .day(_, items) = model.rows[3] else { Issue.record("not a day"); return }
        #expect(items.map(\.capturedAt) == [Self.lateInNewYork.addingTimeInterval(-3600), Self.lateInNewYork])
    }
}
