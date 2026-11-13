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
public struct CapturedPhoto: Codable, Equatable, Sendable {
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
public struct CapturedVideo: Codable, Equatable, Sendable {
    public var mainURL: URL
    public var mainPosition: CameraPosition
    public var selfieURL: URL?
    /// Seconds recorded in the main stream.
    public var duration: TimeInterval
    /// How much later the selfie stream started than the main one, in seconds (negative: earlier).
    public var selfieOffset: TimeInterval
    /// Microphone audio, in the main stream only.
    public var hasAudio: Bool
    /// Why the recording ended early; the part before is kept (C13d). Nil for a stop or the time limit.
    public var interruption: CaptureInterruption?

    public init(
        mainURL: URL, mainPosition: CameraPosition, selfieURL: URL?, duration: TimeInterval,
        selfieOffset: TimeInterval, hasAudio: Bool, interruption: CaptureInterruption? = nil
    ) {
        self.interruption = interruption
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
    /// Too little free space to start a recording.
    case lowStorage
}

/// What took the camera away (doc 01: call, app switching, overheating, low disk space).
public enum CaptureInterruption: String, Codable, Sendable {
    /// A call or another app is using the camera or microphone.
    case anotherApp
    /// MimoDays went to the background.
    case background
    /// The iPhone got too warm.
    case tooWarm
    /// The disk filled up while recording.
    case lowStorage
    case other
}

/// Something the camera screen should react to.
public enum CaptureEvent: Equatable, Sendable {
    /// The engine changed cameras on its own, e.g. dropped the selfie camera under heavy load.
    case setupChanged(CameraSetup)
    /// The camera stopped delivering; a recording in progress ends and keeps what it has.
    case interrupted(CaptureInterruption)
    /// The camera is back after an interruption or a media services reset.
    case resumed
}

/// How much a recording may write (doc 01: handle low disk space). Pure, so it is tested without a disk.
public enum CaptureStorage {
    /// Left free for the system and for saving the moment.
    public static let reserve: Int64 = 200_000_000
    /// Less than this per stream isn't worth starting (a few seconds of video).
    public static let minimumPerStream: Int64 = 20_000_000

    /// The largest file each stream may grow to, or nil when there isn't room to record.
    public static func budgetPerStream(freeBytes: Int64, streams: Int) -> Int64? {
        guard streams > 0 else { return nil }
        let perStream = (freeBytes - reserve) / Int64(streams)
        return perStream >= minimumPerStream ? perStream : nil
    }

    /// Free space for the temporary capture files, as iOS counts it for important work.
    public static func freeBytes() -> Int64? {
        let values = try? FileManager.default.temporaryDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }
}

/// How the engine reacts to heat and load (doc 01: degrade gracefully). Pure, so it is tested without cameras.
public enum CapturePressurePolicy {
    /// Mirrors `AVCaptureDevice.SystemPressureState.Level`.
    public enum Level: Int, Comparable, Sendable {
        case nominal, fair, serious, critical, shutdown

        public static func < (lhs: Level, rhs: Level) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    public struct Response: Equatable, Sendable {
        public var frameRate: Int
        /// Keep only the rear camera. Never mid-recording: that would break the clip.
        public var dropsSelfie: Bool
    }

    /// Low Power Mode counts as at least serious pressure: a lower frame rate saves battery.
    public static func response(to level: Level, lowPower: Bool = false, setup: CameraSetup, isRecording: Bool) -> Response {
        switch lowPower ? max(level, .serious) : level {
        case .nominal, .fair: Response(frameRate: 30, dropsSelfie: false)
        case .serious: Response(frameRate: 24, dropsSelfie: false)
        case .critical, .shutdown: Response(frameRate: 15, dropsSelfie: setup == .dual && !isRecording)
        }
    }

    /// Format widths tried for each camera of a dual setup, largest first, before keeping one camera.
    public static let dualFormatWidths: [Int32] = [1920, 1280, 640]
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
    /// Flash applies to the rear camera only. `silent` suppresses the shutter sound where iOS allows it.
    func capturePhoto(flash: Bool, silent: Bool) async throws -> CapturedPhoto
    /// Records until `stopRecording()` is called or `limit` is reached, then returns the clip.
    func record(limit: Duration?) async throws -> CapturedVideo
    func stopRecording() async
    /// Live preview of one camera for the UI to host; nil when that camera isn't in the setup.
    @MainActor func previewLayer(for position: CameraPosition) -> CALayer?
    /// Changes the camera screen should show. One listener.
    var events: AsyncStream<CaptureEvent> { get }
}

/// Where capture writes its files until a moment is saved.
public enum CaptureFiles {
    /// A fresh file for captured media in the temporary directory.
    public static func temporaryURL(_ fileExtension: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Capture", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("\(UUID().uuidString).\(fileExtension)")
    }
}
