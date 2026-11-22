import Foundation

/// P8.1: "Open MimoDays Camera" from Siri, Shortcuts, the Action button, Control Center or the Lock Screen. The
/// intent runs in the app, maybe before `RootView` is up, so it leaves a request that `RootView` takes once; triggers
/// that come before it's taken are one request.
@MainActor
public enum CameraShortcut {
    static var isPending = false
    /// Windows (iPad) with the camera or Review up: a shortcut never opens a second camera.
    static var openCameras = 0
    static let requested = Notification.Name("MimoDays.cameraShortcut")

    public static func request() {
        isPending = true
        NotificationCenter.default.post(name: requested, object: nil)
    }

    /// A plain camera: no prompt, so never a surprise.
    static let route = Route.capture(promptID: nil)

    /// True once per request. A window in the background leaves it to one in front; with a camera up in any window
    /// the request is spent without opening another.
    static func take(inBackground: Bool = false) -> Bool {
        guard !inBackground else { return false }
        defer { isPending = false }
        return isPending && openCameras == 0
    }
}
