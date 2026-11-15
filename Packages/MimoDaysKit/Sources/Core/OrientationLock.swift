import UIKit

/// The interface orientations the app allows right now. The capture flow keeps the screen upright and the camera
/// turns its own controls with the phone (C.3), like the Camera app; everywhere else the app rotates as before.
/// The app delegate reports `mask` to iOS.
@MainActor
public enum OrientationLock {
    /// Nil: what Info.plist allows.
    private static var locked: UIInterfaceOrientationMask?

    public static var mask: UIInterfaceOrientationMask {
        locked ?? (UIDevice.current.userInterfaceIdiom == .pad ? .all : .allButUpsideDown)
    }

    /// How the window is turned, as a hold: upright on iPhone while locked; on iPad it turns with the device.
    public static var windowHold: DeviceHold {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        // An interface turned left has the home side on the left: the top of the device to the right.
        return switch scene?.effectiveGeometry.interfaceOrientation {
        case .landscapeLeft: .landscapeRight
        case .landscapeRight: .landscapeLeft
        default: .upright
        }
    }

    /// Locks to `mask`, or unlocks with nil, and turns the screen if it has to.
    public static func set(_ mask: UIInterfaceOrientationMask?) {
        locked = mask
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            var top = scene.keyWindow?.rootViewController
            while let presented = top?.presentedViewController { top = presented }
            top?.setNeedsUpdateOfSupportedInterfaceOrientations()
            scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            if let mask { scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { _ in } }
        }
    }
}
