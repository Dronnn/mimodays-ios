import Core
import Persistence
import SwiftData

/// Everything one launch shares, built once by the app and handed to `RootView`.
@MainActor
public final class AppDependencies {
    let modelContainer: ModelContainer
    let permissions: any PermissionService
    let skipsOnboarding: Bool

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
    }
}
