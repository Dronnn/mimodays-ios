import AppFeature
import Core
import SwiftUI
import UIKit

@main
struct MimoDaysApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let dependencies: AppDependencies

    init() {
        let configuration = LaunchConfiguration()
        if configuration.isUITesting {
            UIView.setAnimationsEnabled(false)
        }
        dependencies = AppDependencies(configuration: configuration)
    }

    var body: some Scene {
        WindowGroup {
            RootView(dependencies: dependencies)
        }
    }
}

/// Reports the orientations the app allows right now: upright only while capturing (C.3).
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_: UIApplication, supportedInterfaceOrientationsFor _: UIWindow?) -> UIInterfaceOrientationMask {
        OrientationLock.mask
    }
}
