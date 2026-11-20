import AppFeature
import Core
import SwiftUI
import UIKit

@main
struct MimoDaysApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let configuration = LaunchConfiguration()
    /// Nil when the store can't be opened: the launch offers a way back instead of crashing.
    private let dependencies: AppDependencies?

    init() {
        if configuration.isUITesting {
            UIView.setAnimationsEnabled(false)
        }
        dependencies = try? AppDependencies(configuration: configuration)
    }

    var body: some Scene {
        WindowGroup {
            AppLaunchView(configuration: configuration, opened: dependencies)
        }
    }
}

/// Reports the orientations the app allows right now: upright only while capturing (C.3).
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_: UIApplication, supportedInterfaceOrientationsFor _: UIWindow?) -> UIInterfaceOrientationMask {
        OrientationLock.mask
    }
}
