import AppFeature
import Core
import SwiftUI
import UIKit

@main
struct MimoDaysApp: App {
    init() {
        if LaunchConfiguration().isUITesting {
            UIView.setAnimationsEnabled(false)
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
