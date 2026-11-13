import AVFoundation
import CoreLocation
import Photos
import UserNotifications

/// Device permissions MimoDays asks for, each at the point of use (never all at launch).
public enum Permission: String, CaseIterable, Sendable {
    case camera
    case microphone
    /// Add-only: saving exports to Photos. Importing goes through the system picker and needs no permission.
    case photoLibrary
    /// When in use only.
    case location
    case notifications
}

public enum PermissionStatus: String, Equatable, Sendable {
    case notDetermined
    case granted
    /// Works with less: approximate location, provisional notifications.
    case limited
    case denied
    /// Blocked by Screen Time or a device profile; the person may not be able to change it.
    case restricted

    public var isUsable: Bool { self == .granted || self == .limited }
    /// Asking again won't show a system prompt; only Settings can change it.
    public var needsSettings: Bool { self == .denied || self == .restricted }
}

public protocol PermissionService: Sendable {
    func status(of permission: Permission) async -> PermissionStatus
    /// Shows the system prompt when the status is not determined; otherwise returns the current status.
    func request(_ permission: Permission) async -> PermissionStatus
}

// MARK: System

public struct SystemPermissionService: PermissionService {
    public init() {}

    public func status(of permission: Permission) async -> PermissionStatus {
        switch permission {
        case .camera: PermissionStatus(AVCaptureDevice.authorizationStatus(for: .video))
        case .microphone: PermissionStatus(AVCaptureDevice.authorizationStatus(for: .audio))
        case .photoLibrary: PermissionStatus(PHPhotoLibrary.authorizationStatus(for: .addOnly))
        case .location: await MainActor.run { LocationAuthorization.shared.status }
        case .notifications: PermissionStatus(await UNUserNotificationCenter.current().notificationSettings().authorizationStatus)
        }
    }

    public func request(_ permission: Permission) async -> PermissionStatus {
        switch permission {
        case .camera:
            _ = await AVCaptureDevice.requestAccess(for: .video)
        case .microphone:
            _ = await AVCaptureDevice.requestAccess(for: .audio)
        case .photoLibrary:
            _ = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        case .location:
            await LocationAuthorization.shared.request()
        case .notifications:
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        }
        return await status(of: permission)
    }
}

/// Core Location reports authorization through a delegate on the main thread.
@MainActor
private final class LocationAuthorization: NSObject, CLLocationManagerDelegate {
    static let shared = LocationAuthorization()

    private let manager = CLLocationManager()
    private var waiters: [CheckedContinuation<Void, Never>] = []

    override private init() {
        super.init()
        manager.delegate = self
    }

    var status: PermissionStatus {
        PermissionStatus(manager.authorizationStatus, accuracy: manager.accuracyAuthorization)
    }

    func request() async {
        guard manager.authorizationStatus == .notDetermined else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
            manager.requestWhenInUseAuthorization()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_: CLLocationManager) {
        // The manager was created on the main thread, so its callbacks arrive there.
        MainActor.assumeIsolated {
            guard manager.authorizationStatus != .notDetermined else { return }
            let resumed = waiters
            waiters.removeAll()
            resumed.forEach { $0.resume() }
        }
    }
}

// MARK: Mapping (unit-tested for every state)

public extension PermissionStatus {
    init(_ status: AVAuthorizationStatus) {
        switch status {
        case .notDetermined: self = .notDetermined
        case .authorized: self = .granted
        case .denied: self = .denied
        case .restricted: self = .restricted
        @unknown default: self = .denied
        }
    }

    init(_ status: PHAuthorizationStatus) {
        switch status {
        case .notDetermined: self = .notDetermined
        case .authorized: self = .granted
        case .limited: self = .limited
        case .denied: self = .denied
        case .restricted: self = .restricted
        @unknown default: self = .denied
        }
    }

    init(_ status: CLAuthorizationStatus, accuracy: CLAccuracyAuthorization) {
        switch status {
        case .notDetermined: self = .notDetermined
        case .authorizedWhenInUse, .authorizedAlways: self = accuracy == .fullAccuracy ? .granted : .limited
        case .denied: self = .denied
        case .restricted: self = .restricted
        @unknown default: self = .denied
        }
    }

    init(_ status: UNAuthorizationStatus) {
        switch status {
        case .notDetermined: self = .notDetermined
        case .authorized: self = .granted
        case .provisional, .ephemeral: self = .limited
        case .denied: self = .denied
        @unknown default: self = .denied
        }
    }
}

// MARK: Preset

/// Fixed answers instead of system prompts: UI tests and previews.
public actor PresetPermissionService: PermissionService {
    private var statuses: [Permission: PermissionStatus]
    private let requestResult: PermissionStatus

    /// Every permission starts at `status`; a request turns a not-determined one into `requestResult`.
    public init(status: PermissionStatus, requestResult: PermissionStatus = .granted) {
        statuses = Dictionary(uniqueKeysWithValues: Permission.allCases.map { ($0, status) })
        self.requestResult = requestResult
    }

    public func status(of permission: Permission) -> PermissionStatus {
        statuses[permission] ?? .notDetermined
    }

    public func request(_ permission: Permission) -> PermissionStatus {
        if statuses[permission] == .notDetermined { statuses[permission] = requestResult }
        return status(of: permission)
    }
}
