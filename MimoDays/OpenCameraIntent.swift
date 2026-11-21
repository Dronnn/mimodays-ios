import AppIntents
#if !WIDGET_EXTENSION
import AppFeature
#endif

/// P8.1: the normal MimoDays camera from Siri, Shortcuts, the Action button, Control Center or the Lock Screen.
/// Built into the app and the widget extension (its control runs it); it always runs in the app, which opens.
struct OpenCameraIntent: AppIntent {
    static let title: LocalizedStringResource = "Open MimoDays Camera"
    static let description = IntentDescription("Opens the MimoDays camera, ready to take a moment.")
    static let openAppWhenRun = true
    /// From the Lock Screen the iPhone is unlocked first; App Lock then asks in the app as usual.
    static let authenticationPolicy = IntentAuthenticationPolicy.requiresLocalDeviceAuthentication

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        CameraShortcut.request()
        #endif
        return .result()
    }
}

#if !WIDGET_EXTENSION
/// Siri and Shortcuts without setup; the Action button picks it from the shortcuts.
struct MimoDaysShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenCameraIntent(),
            phrases: [
                "Open \(.applicationName) Camera",
                "Open the \(.applicationName) camera",
                "Take a moment with \(.applicationName)",
            ],
            shortTitle: "MimoDays Camera",
            systemImageName: "camera"
        )
    }
}
#endif
