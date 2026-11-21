import Foundation

/// P8.1: "Open MimoDays Camera" from Siri, Shortcuts, the Action button, Control Center or the Lock Screen. The
/// intent runs in the app, maybe before `RootView` is up, so it leaves a request that `RootView` takes once; triggers
/// that come before it's taken are one request.
@MainActor
public enum CameraShortcut {
    static var isPending = false
    static let requested = Notification.Name("MimoDays.cameraShortcut")

    public static func request() {
        isPending = true
        NotificationCenter.default.post(name: requested, object: nil)
    }

    /// A plain camera: no prompt, so never a surprise.
    static let route = Route.capture(promptID: nil)

    /// True once per request.
    static func take() -> Bool {
        defer { isPending = false }
        return isPending
    }
}
