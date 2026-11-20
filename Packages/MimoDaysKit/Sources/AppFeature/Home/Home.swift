import Foundation
import Observation

/// The two sides of the first tab (U10-U15): Today and the Mosaic.
enum HomeSide: String, Codable, Sendable {
    case today
    case mosaic
}

/// This iPhone's home: the side last shown.
struct HomeSettings: Codable, Equatable, Sendable {
    var side = HomeSide.today
}

typealias HomePreferences = DevicePreference<HomeSettings>

extension DevicePreference<HomeSettings> {
    static func home(_ defaults: UserDefaults?) -> HomePreferences {
        HomePreferences(key: "homeSettings", defaults: defaults, initial: HomeSettings())
    }
}

/// The side the first tab shows, chosen with the header's Today | Mosaic switch and remembered on this device. The
/// sides change over at once: no turn, no drag (Andrew, 2026-11-15).
@MainActor
@Observable
final class Home {
    private(set) var side: HomeSide
    @ObservationIgnored private let preferences: HomePreferences?

    init(preferences: HomePreferences?) {
        self.preferences = preferences
        side = preferences?.value.side ?? .today
    }

    func show(_ side: HomeSide) {
        self.side = side
        preferences?.value.side = side
    }

    /// S08 Delete all data: back to Today, as on first launch (the setting itself is reset with the others).
    func reset() {
        side = .today
    }
}
