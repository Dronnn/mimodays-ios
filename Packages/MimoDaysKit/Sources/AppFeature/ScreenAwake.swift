import SwiftUI
import UIKit

/// P8.20: the screen stays on while something runs that the user waits for without touching it - a recording stopped
/// when the screen dimmed half way through a minute. Everywhere else it dims as usual.
@MainActor
enum ScreenAwake {
    /// Tests set it.
    static var apply: (Bool) -> Void = { UIApplication.shared.isIdleTimerDisabled = $0 }
    private static var holders = 0

    static func hold() {
        holders += 1
        if holders == 1 { apply(true) }
    }

    static func release() {
        guard holders > 0 else { return }
        holders -= 1
        if holders == 0 { apply(false) }
    }
}

extension View {
    /// The screen stays on while `active` is true and this view is on screen.
    func keepsScreenOn(_ active: Bool = true) -> some View {
        modifier(KeepsScreenOn(active: active))
    }
}

private struct KeepsScreenOn: ViewModifier {
    let active: Bool
    @State private var holds = false

    func body(content: Content) -> some View {
        content
            .onAppear { set(active) }
            .onChange(of: active) { _, active in set(active) }
            .onDisappear { set(false) }
    }

    private func set(_ on: Bool) {
        guard on != holds else { return }
        holds = on
        if on { ScreenAwake.hold() } else { ScreenAwake.release() }
    }
}
