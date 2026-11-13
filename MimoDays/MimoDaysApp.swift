import AppFeature
import Core
import SwiftUI
import UIKit

@main
struct MimoDaysApp: App {
    private let configuration = LaunchConfiguration()

    init() {
        if configuration.isUITesting {
            UIView.setAnimationsEnabled(false)
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView(permissions: permissions)
        }
    }

    /// UI tests can start every permission in a fixed state instead of hitting system prompts.
    private var permissions: any PermissionService {
        if configuration.isUITesting, let status = configuration.permissions {
            return PresetPermissionService(status: status)
        }
        return SystemPermissionService()
    }
}
