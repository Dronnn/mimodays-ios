import Foundation
import Observation
import os

/// A setting of this iPhone, not part of the archive: kept in UserDefaults as JSON (in memory when `defaults` is
/// nil, for UI tests). Saved on every change.
@MainActor
@Observable
final class DevicePreference<Value: Codable & Equatable & Sendable> {
    var value: Value {
        didSet { if value != oldValue { save() } }
    }

    @ObservationIgnored private let key: String
    @ObservationIgnored private let defaults: UserDefaults?
    private static var logger: Logger { Logger(subsystem: "MimoDays", category: "Settings") }

    init(key: String, defaults: UserDefaults?, initial: Value) {
        self.key = key
        self.defaults = defaults
        guard let data = defaults?.data(forKey: key) else {
            value = initial
            return
        }
        do {
            value = try JSONDecoder().decode(Value.self, from: data)
        } catch {
            Self.logger.error("Reading the \(key, privacy: .public) setting failed: \(error.localizedDescription, privacy: .public)")
            value = initial
        }
    }

    private func save() {
        guard let defaults else { return }
        do {
            defaults.set(try JSONEncoder().encode(value), forKey: key)
        } catch {
            Self.logger.error("Saving the \(self.key, privacy: .public) setting failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
