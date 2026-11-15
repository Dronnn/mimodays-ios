import Core
import Foundation
import Persistence
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

    /// The largest video format the camera may use. Two cameras at once never get more than 1080p.
    enum VideoQuality: String, Codable, CaseIterable, Sendable {
        case hd720
        case hd1080

        var maxFormatWidth: Int32 {
            switch self {
            case .hd720: 1280
            case .hd1080: 1920
            }
        }
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
    var videoQuality = VideoQuality.hd1080
    var recordsSound = true
    var cameraSounds = false
    var selfieWindow = SelfieWindow()
    /// U01: the recording format; remembered on this device.
    var format = CaptureFormat.portrait

    init() {}

    /// Settings saved by an earlier version lack the newer keys; those keep their defaults.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        opensIn = try container.decodeIfPresent(Mode.self, forKey: .opensIn) ?? opensIn
        videoLength = try container.decodeIfPresent(VideoLength.self, forKey: .videoLength) ?? videoLength
        videoQuality = try container.decodeIfPresent(VideoQuality.self, forKey: .videoQuality) ?? videoQuality
        recordsSound = try container.decodeIfPresent(Bool.self, forKey: .recordsSound) ?? recordsSound
        cameraSounds = try container.decodeIfPresent(Bool.self, forKey: .cameraSounds) ?? cameraSounds
        selfieWindow = try container.decodeIfPresent(SelfieWindow.self, forKey: .selfieWindow) ?? selfieWindow
        format = try container.decodeIfPresent(CaptureFormat.self, forKey: .format) ?? format
    }
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

/// What the camera needs from the app: an engine for each time it opens, the settings and the review draft.
struct CameraServices {
    var makeEngine: @MainActor () -> any CaptureEngine
    /// How the phone is held, for the recording formats.
    var makeOrientation: @MainActor () -> any OrientationSensor = { FixedOrientationSensor() }
    var settings: any CameraSettingsStore
    /// Where a capture in review waits, so it survives the app being closed.
    var drafts: ReviewDraftStore
    var voice: VoiceServices
    var places: PlaceServices

    /// Previews and anything without a device camera.
    @MainActor static var simulated: CameraServices {
        CameraServices(
            makeEngine: { SimulatedCaptureEngine() }, settings: InMemoryCameraSettingsStore(),
            drafts: ReviewDraftStore(root: FileManager.default.temporaryDirectory.appending(path: "Review-\(UUID().uuidString)")),
            voice: .simulated,
            places: .simulated
        )
    }
}

/// C09/C10: the recorder and the on-device transcriber.
struct VoiceServices {
    var makeRecorder: @MainActor () -> any VoiceRecorder
    var transcriber: any VoiceTranscriber

    @MainActor static var simulated: VoiceServices {
        VoiceServices(makeRecorder: { SimulatedVoiceRecorder() }, transcriber: SimulatedTranscriber())
    }
}

extension EnvironmentValues {
    @Entry var camera: CameraServices?
}
