import Foundation
import QuartzCore

public enum CameraPosition: String, Codable, CaseIterable, Sendable {
    case back
    case front

    public var other: CameraPosition { self == .back ? .front : .back }
}

/// What the camera session runs with.
public enum CameraSetup: Equatable, Sendable {
    /// Rear frame with the front camera in the selfie window.
    case dual
    /// One camera at a time: devices without multi-camera support (Andrew, 2026-11-13: rear first, flip to front).
    case single(CameraPosition)

    /// Cameras in use, main frame first.
    public var positions: [CameraPosition] {
        switch self {
        case .dual: [.back, .front]
        case let .single(position): [position]
        }
    }
}

/// A photo straight from the cameras, in a temporary file until the moment is saved.
public struct CapturedPhoto: Equatable, Sendable {
    /// The main frame: the rear camera, or whichever camera a single-camera setup used.
    public var mainURL: URL
    public var mainPosition: CameraPosition
    /// The front camera's frame on dual captures.
    public var selfieURL: URL?

    public init(mainURL: URL, mainPosition: CameraPosition, selfieURL: URL?) {
        self.mainURL = mainURL
        self.mainPosition = mainPosition
        self.selfieURL = selfieURL
    }
}

/// A clip with one file per camera (separate streams), in temporary files until the moment is saved.
public struct CapturedVideo: Equatable, Sendable {
    public var mainURL: URL
    public var mainPosition: CameraPosition
    public var selfieURL: URL?
    /// Seconds recorded in the main stream.
    public var duration: TimeInterval
    /// How much later the selfie stream started than the main one, in seconds (negative: earlier).
    public var selfieOffset: TimeInterval
    /// Microphone audio, in the main stream only.
    public var hasAudio: Bool

    public init(
        mainURL: URL, mainPosition: CameraPosition, selfieURL: URL?, duration: TimeInterval,
        selfieOffset: TimeInterval, hasAudio: Bool
    ) {
        self.mainURL = mainURL
        self.mainPosition = mainPosition
        self.selfieURL = selfieURL
        self.duration = duration
        self.selfieOffset = selfieOffset
        self.hasAudio = hasAudio
    }
}

public enum CaptureError: Error, Equatable, Sendable {
    /// No usable camera (simulator, or the hardware is busy or broken).
    case cameraUnavailable
    case configurationFailed
    /// `start()` hasn't run, or the session stopped.
    case notRunning
    case alreadyRecording
    case photoFailed
    case recordingFailed
}

/// The camera, behind a protocol so the UI can run on a simulated engine (simulator, UI tests).
public protocol CaptureEngine: AnyObject, Sendable {
    /// Configures and starts the session: dual when the device supports it, otherwise the rear camera.
    /// Calling it again restarts a stopped session with the same setup.
    func start() async throws -> CameraSetup
    func stop() async
    /// Switches to the other camera. Single-camera setups only; a dual setup is returned unchanged.
    func flip() async throws -> CameraSetup
    /// Adds or removes the microphone. Only with permission, and only for video.
    func setMicrophone(_ enabled: Bool) async throws
    /// Flash applies to the rear camera only.
    func capturePhoto(flash: Bool) async throws -> CapturedPhoto
    /// Records until `stopRecording()` is called or `limit` is reached, then returns the clip.
    func record(limit: Duration?) async throws -> CapturedVideo
    func stopRecording() async
    /// Live preview of one camera for the UI to host; nil when that camera isn't in the setup.
    @MainActor func previewLayer(for position: CameraPosition) -> CALayer?
}

extension CaptureEngine {
    /// A fresh file for captured media in the temporary directory.
    static func temporaryURL(_ fileExtension: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Capture", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("\(UUID().uuidString).\(fileExtension)")
    }
}
