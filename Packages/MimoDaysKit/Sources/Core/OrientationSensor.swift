import CoreMotion
import Foundation
import UIKit

/// How the phone is physically held. The camera follows it like the Camera app, even with rotation lock on
/// (Andrew, 2026-11-15). Upside down counts as upright; flat on a table keeps the last hold.
public enum DeviceHold: String, Sendable, Equatable, CaseIterable {
    case upright
    /// The top of the phone to the left.
    case landscapeLeft
    /// The top of the phone to the right.
    case landscapeRight

    public var isLandscape: Bool { self != .upright }

    /// The hold for a gravity vector in the phone's coordinates (x to the right edge, y to the top, z out of the
    /// screen). It changes only well past the diagonal, so holding the phone at about 45° doesn't flicker.
    public static func from(gravityX x: Double, y: Double, z: Double, previous: DeviceHold) -> DeviceHold {
        if abs(z) > 0.8 { return previous }
        let switchRatio = 1.4
        // Top to the left puts the left edge down: gravity points to -x.
        if abs(x) > abs(y) * switchRatio { return x < 0 ? .landscapeLeft : .landscapeRight }
        if abs(y) > abs(x) * switchRatio { return .upright }
        return previous
    }
}

/// Reports how the phone is held: the current hold first, then each change. One listener.
public protocol OrientationSensor: AnyObject, Sendable {
    var holds: AsyncStream<DeviceHold> { get }
}

/// Tests, previews and the simulator's UI tests: holds the phone the way it's told.
public final class FixedOrientationSensor: OrientationSensor, @unchecked Sendable {
    private let lock = NSLock()
    private var current: DeviceHold
    private var continuation: AsyncStream<DeviceHold>.Continuation?

    public init(_ hold: DeviceHold = .upright) {
        current = hold
    }

    public var holds: AsyncStream<DeviceHold> {
        let (stream, continuation) = AsyncStream.makeStream(of: DeviceHold.self, bufferingPolicy: .bufferingNewest(1))
        lock.withLock {
            self.continuation = continuation
            continuation.yield(current)
        }
        return stream
    }

    public func set(_ hold: DeviceHold) {
        lock.withLock {
            current = hold
            continuation?.yield(hold)
        }
    }
}

/// The device: gravity from Core Motion, which keeps working with rotation lock on. Where there's no motion data
/// (the simulator), the device orientation that iOS reports.
public final class MotionOrientationSensor: OrientationSensor, @unchecked Sendable {
    private let motion = CMMotionManager()
    /// Main actor only.
    private var observer: (any NSObjectProtocol)?

    public init() {}

    public var holds: AsyncStream<DeviceHold> {
        let (stream, continuation) = AsyncStream.makeStream(of: DeviceHold.self, bufferingPolicy: .bufferingNewest(1))
        if motion.isDeviceMotionAvailable {
            var last = DeviceHold.upright
            continuation.yield(last)
            motion.deviceMotionUpdateInterval = 0.1
            motion.startDeviceMotionUpdates(to: .main) { data, _ in
                guard let gravity = data?.gravity else { return }
                let hold = DeviceHold.from(gravityX: gravity.x, y: gravity.y, z: gravity.z, previous: last)
                if hold != last {
                    last = hold
                    continuation.yield(hold)
                }
            }
            continuation.onTermination = { [self] _ in motion.stopDeviceMotionUpdates() }
        } else {
            Task { @MainActor in
                let device = UIDevice.current
                device.beginGeneratingDeviceOrientationNotifications()
                var last = Self.hold(device.orientation, previous: .upright)
                continuation.yield(last)
                observer = NotificationCenter.default.addObserver(
                    forName: UIDevice.orientationDidChangeNotification, object: nil, queue: .main
                ) { _ in
                    MainActor.assumeIsolated {
                        let hold = Self.hold(UIDevice.current.orientation, previous: last)
                        if hold != last {
                            last = hold
                            continuation.yield(hold)
                        }
                    }
                }
                continuation.onTermination = { [self] _ in
                    Task { @MainActor in
                        if let observer { NotificationCenter.default.removeObserver(observer) }
                        observer = nil
                        UIDevice.current.endGeneratingDeviceOrientationNotifications()
                    }
                }
            }
        }
        return stream
    }

    private static func hold(_ orientation: UIDeviceOrientation, previous: DeviceHold) -> DeviceHold {
        switch orientation {
        case .portrait, .portraitUpsideDown: .upright
        case .landscapeLeft: .landscapeLeft
        case .landscapeRight: .landscapeRight
        default: previous
        }
    }
}
