import AppFeature
import Core
import SwiftUI
import UIKit

@main
struct MimoDaysApp: App {
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
