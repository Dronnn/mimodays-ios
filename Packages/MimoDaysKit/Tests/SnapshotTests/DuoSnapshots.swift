@testable import AppFeature
import SwiftUI
import TestSupport

/// iPhone Duo: the outer display, and the inner one open in landscape. Neither has a status bar above the content,
/// which RootView tells every screen; a screen snapshotted on its own is told here.
extension SnapshotVariant {
    static let duo = [SnapshotVariant(.duoOuter, .light), SnapshotVariant(.duoInner, .light)]
}

extension View {
    func onDuo() -> some View { environment(\.statusBarOnTop, false) }
}
