import Core
import Persistence
import SwiftData
import UserNotifications

/// Everything one launch shares, built once by the app and handed to `RootView`.
@MainActor
public final class AppDependencies {
    let modelContainer: ModelContainer
    let permissions: any PermissionService
    let skipsOnboarding: Bool
    let surprises: SurpriseCoordinator
    let notificationTaps = SurpriseNotificationHandler()
    let camera: CameraServices
    let momentSaver: MomentSaver

    public init(configuration: LaunchConfiguration = LaunchConfiguration()) {
        do {
            // UI tests start from an empty store on every launch.
            modelContainer = try MimoDaysStore.makeContainer(inMemory: configuration.isUITesting)
        } catch {
            fatalError("MimoDays can't open its store: \(error)")
        }
        // UI tests can start every permission in a fixed state instead of hitting system prompts.
        if configuration.isUITesting, let status = configuration.permissions {
            permissions = PresetPermissionService(status: status)
        } else {
            permissions = SystemPermissionService()
        }
        skipsOnboarding = configuration.skipsOnboarding
        // UI tests keep notification requests in memory so nothing is left on the simulator.
        let notifications: any NotificationScheduler = configuration.isUITesting
            ? InMemoryNotificationScheduler() : SystemNotificationScheduler()
        surprises = SurpriseCoordinator(context: modelContainer.mainContext, notifications: notifications, permissions: permissions)
        // The simulator has no cameras; UI tests can ask for the simulated one on devices too.
        #if targetEnvironment(simulator)
        let simulatedCamera = true
        #else
        let simulatedCamera = configuration.usesFakeCamera
        #endif
        camera = CameraServices(
            makeEngine: { @MainActor () -> any CaptureEngine in simulatedCamera ? SimulatedCaptureEngine() : AVCaptureEngine() },
            settings: configuration.isUITesting ? InMemoryCameraSettingsStore() : UserDefaultsCameraSettingsStore(),
            drafts: ReviewDraftStore(root: Self.reviewRoot(configuration))
        )
        do {
            momentSaver = MomentSaver(context: modelContainer.mainContext, store: try MediaStore(root: Self.mediaRoot(configuration)))
        } catch {
            fatalError("MimoDays can't open its media folder: \(error)")
        }
        UNUserNotificationCenter.current().delegate = notificationTaps
        if configuration.isUITesting, let tap = configuration.surpriseTap {
            simulate(tap)
        }
    }

    /// Application Support/Media, out of the user's Files view. UI tests use a fresh temporary folder.
    private static func mediaRoot(_ configuration: LaunchConfiguration) -> URL {
        if configuration.isUITesting {
            return FileManager.default.temporaryDirectory.appending(path: "UITestMedia-\(UUID().uuidString)", directoryHint: .isDirectory)
        }
        return URL.applicationSupportDirectory.appending(path: "Media", directoryHint: .isDirectory)
    }

    /// Application Support/Review; UI tests use a fresh temporary folder.
    private static func reviewRoot(_ configuration: LaunchConfiguration) -> URL {
        if configuration.isUITesting {
            return FileManager.default.temporaryDirectory.appending(path: "UITestReview-\(UUID().uuidString)", directoryHint: .isDirectory)
        }
        return URL.applicationSupportDirectory.appending(path: "Review", directoryHint: .isDirectory)
    }

    /// A prompt that fired a minute ago (or 20 minutes ago, so it has expired), then a tap on it.
    private func simulate(_ tap: LaunchConfiguration.SurpriseTap) {
        let planned = Date().addingTimeInterval(tap == .inTime ? -60 : -20 * 60)
        let prompt = SurprisePrompt(plannedAt: planned, expiresAt: planned.addingTimeInterval(15 * 60), notificationRequestID: "ui-test")
        modelContainer.mainContext.insert(prompt)
        try? modelContainer.mainContext.save()
        notificationTaps.deliver(prompt.id)
    }
}
