import Core
import Foundation
import SwiftUI
import os

/// The S03 camera settings, also reachable from the camera's ••• sheet (Andrew, 2026-11-13).
struct CameraSettings: Codable, Equatable, Sendable {
    enum Mode: String, Codable, CaseIterable, Sendable {
        case photo
        case video
    }

    enum VideoLength: Int, Codable, CaseIterable, Sendable {
        case short = 10
        case medium = 30
        case long = 60

        var duration: Duration { .seconds(rawValue) }
    }

    /// Where the selfie window sits and how big it is (C04). Medium in the top right by default.
    struct SelfieWindow: Codable, Equatable, Sendable {
        enum Corner: String, Codable, CaseIterable, Sendable {
            case topLeft
            case topRight
            case bottomLeft
            case bottomRight

            var isTop: Bool { self == .topLeft || self == .topRight }
            var isLeft: Bool { self == .topLeft || self == .bottomLeft }
        }

        /// ±25% around the designed 112 × 150 frame (Andrew, 2026-11-13).
        enum Scale: String, Codable, CaseIterable, Sendable {
            case small
            case medium
            case large

            var factor: CGFloat {
                switch self {
                case .small: 0.75
                case .medium: 1
                case .large: 1.25
                }
            }
        }

        var corner = Corner.topRight
        var scale = Scale.medium
    }

    var opensIn = Mode.photo
    var videoLength = VideoLength.short
    var recordsSound = true
    var cameraSounds = false
    var selfieWindow = SelfieWindow()
}

@MainActor
protocol CameraSettingsStore: AnyObject {
    func load() -> CameraSettings
    func save(_ settings: CameraSettings)
}

/// Device preferences, not part of the archive: kept in UserDefaults.
@MainActor
final class UserDefaultsCameraSettingsStore: CameraSettingsStore {
    private static let key = "cameraSettings"
    private let defaults: UserDefaults
    private let logger = Logger(subsystem: "MimoDays", category: "Camera")

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> CameraSettings {
        guard let data = defaults.data(forKey: Self.key) else { return CameraSettings() }
        do {
            return try JSONDecoder().decode(CameraSettings.self, from: data)
        } catch {
            logger.error("Reading camera settings failed: \(error.localizedDescription, privacy: .public)")
            return CameraSettings()
        }
    }

    func save(_ settings: CameraSettings) {
        do {
            defaults.set(try JSONEncoder().encode(settings), forKey: Self.key)
        } catch {
            logger.error("Saving camera settings failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

@MainActor
final class InMemoryCameraSettingsStore: CameraSettingsStore {
    private(set) var settings: CameraSettings

    init(_ settings: CameraSettings = CameraSettings()) {
        self.settings = settings
    }

    func load() -> CameraSettings { settings }
    func save(_ settings: CameraSettings) { self.settings = settings }
}

/// What the camera needs from the app: an engine for each time it opens, and the settings store.
struct CameraServices {
    var makeEngine: @MainActor () -> any CaptureEngine
    var settings: any CameraSettingsStore

    /// Previews and anything without a device camera.
    @MainActor static var simulated: CameraServices {
        CameraServices(makeEngine: { SimulatedCaptureEngine() }, settings: InMemoryCameraSettingsStore())
    }
}

extension EnvironmentValues {
    @Entry var camera: CameraServices?
}

extension CaptureResult {
    /// Removes the temporary files of a capture nobody keeps.
    func discardFiles() {
        let urls: [URL?] = switch self {
        case let .photo(photo): [photo.mainURL, photo.selfieURL]
        case let .video(video): [video.mainURL, video.selfieURL]
        }
        urls.compactMap(\.self).forEach { try? FileManager.default.removeItem(at: $0) }
    }
}
