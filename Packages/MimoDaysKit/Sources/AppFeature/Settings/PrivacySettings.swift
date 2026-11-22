import Foundation
import Persistence
import SwiftData

/// S05: App Lock and how places are kept.
struct PrivacySettings: Codable, Equatable, Sendable {
    /// How long MimoDays may be away before it asks again.
    enum LockDelay: Int, Codable, CaseIterable, Sendable {
        case immediately = 0
        case oneMinute = 60
        case fifteenMinutes = 900
        case oneHour = 3600

        var seconds: TimeInterval { TimeInterval(rawValue) }
    }

    /// What a new moment keeps of where this iPhone is.
    enum PlacePrecision: String, Codable, CaseIterable, Sendable {
        /// The city and the position rounded to about 1 km.
        case city
        /// The position as measured.
        case exact
    }

    var appLock = false
    var lockAfter = LockDelay.immediately
    var savesPlace = true
    var precision = PlacePrecision.city
    /// P8.2 Show photos in widgets: off until turned on; App Lock keeps it off.
    var widgetPhotos = false

    init() {}

    /// Settings saved by an earlier version lack the newer keys; those keep their defaults.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        appLock = try container.decodeIfPresent(Bool.self, forKey: .appLock) ?? appLock
        lockAfter = try container.decodeIfPresent(LockDelay.self, forKey: .lockAfter) ?? lockAfter
        savesPlace = try container.decodeIfPresent(Bool.self, forKey: .savesPlace) ?? savesPlace
        precision = try container.decodeIfPresent(PlacePrecision.self, forKey: .precision) ?? precision
        widgetPhotos = try container.decodeIfPresent(Bool.self, forKey: .widgetPhotos) ?? widgetPhotos
    }
}

typealias PrivacyPreferences = DevicePreference<PrivacySettings>

extension DevicePreference<PrivacySettings> {
    static func privacy(_ defaults: UserDefaults?) -> PrivacyPreferences {
        PrivacyPreferences(key: "privacySettings", defaults: defaults, initial: PrivacySettings())
    }
}

/// S05 "Remove all places…".
enum PlaceEraser {
    /// How many moments have a place.
    @MainActor
    static func count(_ context: ModelContext) -> Int {
        (try? context.fetchCount(FetchDescriptor<MomentLocation>())) ?? 0
    }

    /// Every moment's place goes; the moments stay. Returns how many there were.
    @MainActor
    @discardableResult
    static func removeAll(_ context: ModelContext) throws -> Int {
        let locations = try context.fetch(FetchDescriptor<MomentLocation>())
        for location in locations {
            location.moment?.location = nil
            context.delete(location)
        }
        try context.save()
        return locations.count
    }
}
