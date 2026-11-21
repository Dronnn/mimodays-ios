import Core
import Foundation
import Persistence
import SwiftData

/// S09: how Memories opens and sorts, whether Today shows On this day, and which time zone decides a moment's day.
struct MemoriesSettings: Codable, Equatable, Sendable {
    enum Mode: String, Codable, CaseIterable, Sendable {
        case timeline
        case calendar

        var memoriesMode: MemoriesMode { self == .timeline ? .timeline : .calendar }
    }

    /// Which day a moment belongs to.
    enum Days: String, Codable, CaseIterable, Sendable {
        /// Where it was taken: 11 PM in New York stays on that day, wherever you are now.
        case whereTaken
        /// The iPhone's time zone now.
        case thisIPhone
    }

    var opensIn = Mode.timeline
    var newestFirst = true
    var onThisDayOnToday = true
    var days = Days.whereTaken

    init() {}

    /// Settings saved by an earlier version lack the newer keys; those keep their defaults.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        opensIn = try container.decodeIfPresent(Mode.self, forKey: .opensIn) ?? opensIn
        newestFirst = try container.decodeIfPresent(Bool.self, forKey: .newestFirst) ?? newestFirst
        onThisDayOnToday = try container.decodeIfPresent(Bool.self, forKey: .onThisDayOnToday) ?? onThisDayOnToday
        days = try container.decodeIfPresent(Days.self, forKey: .days) ?? days
    }
}

/// The S09 settings for the whole app.
typealias MemoriesPreferences = DevicePreference<MemoriesSettings>

extension DevicePreference<MemoriesSettings> {
    static func memories(_ defaults: UserDefaults?) -> MemoriesPreferences {
        MemoriesPreferences(key: "memoriesSettings", defaults: defaults, initial: MemoriesSettings())
    }
}

/// Each moment's stored day (`localDay`, which Memories, the calendar, On this day and movies all go by) for
/// the S09 time zone choice.
enum MomentDays {
    /// Rewrites the days that differ; returns how many did. `deviceZone` is the iPhone's zone now.
    @MainActor
    @discardableResult
    static func relabel(_ context: ModelContext, days: MemoriesSettings.Days, deviceZone: TimeZone = .current) throws -> Int {
        var changed = 0
        var oldDays: [UUID: Int] = [:]
        for moment in try context.fetch(FetchDescriptor<Moment>()) {
            let zone = days == .thisIPhone ? deviceZone : TimeZone(identifier: moment.timeZoneID) ?? .gmt
            let day = LocalDay(moment.capturedAt, in: zone).key
            if moment.localDay != day {
                oldDays[moment.id] = moment.localDay
                moment.localDay = day
                changed += 1
            }
        }
        // P8.3: a hidden day goes where its moments went, in the same save.
        if changed > 0 {
            do {
                try MemoryVisibility.remapHiddenDays(context, oldDays: oldDays)
                try context.save()
            } catch {
                // All of it or none: new days left unsaved would go out with the next save, without their hidden days.
                context.rollback()
                throw error
            }
        }
        return changed
    }

    /// P8.3: how many moments the change would newly put under a hidden day (they'd leave On this day, widgets and
    /// automatic movies), told before the change. Moments hidden by now, or deleted, don't count.
    @MainActor
    static func newlyHidden(_ context: ModelContext, days: MemoriesSettings.Days, deviceZone: TimeZone = .current) throws -> Int {
        let hidden = Set(try context.fetch(FetchDescriptor<HiddenDay>()).map(\.localDay))
        guard !hidden.isEmpty else { return 0 }
        let moments = try context.fetch(FetchDescriptor<Moment>())
        let moves = moments.map { moment in
            let zone = days == .thisIPhone ? deviceZone : TimeZone(identifier: moment.timeZoneID) ?? .gmt
            return (from: moment.localDay, to: LocalDay(moment.capturedAt, in: zone).key)
        }
        let after = MemoryVisibility.remapped(hidden, moves)
        return zip(moments, moves).filter { moment, move in
            moment.deletedAt == nil && !moment.isHiddenFromMemories && !hidden.contains(move.from) && after.contains(move.to)
        }.count
    }
}
