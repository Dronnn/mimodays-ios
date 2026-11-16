import SwiftUI

extension EnvironmentValues {
    /// Whether the status bar sits above the app's content. iPhone Duo's outer display puts it on the side, with the
    /// tab bar (HIG, Designing for iPhone Duo), so nothing is above the content there.
    @Entry var statusBarOnTop = true
}

extension View {
    /// Pulls a screen's top row up by `amount`, level with the status bar's bottom as drawn for iPhone. Without a
    /// status bar above (iPhone Duo's outer display) the row keeps `StatusBarLift.edgeMargin` from the display's edge
    /// instead of running off it. `compactOnly`: the lift is drawn for iPhone only; iPad keeps the row where it is.
    func statusBarLift(_ amount: CGFloat, compactOnly: Bool = true) -> some View {
        modifier(StatusBarLift(amount: amount, compactOnly: compactOnly))
    }
}

struct StatusBarLift: ViewModifier {
    let amount: CGFloat
    let compactOnly: Bool
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.statusBarOnTop) private var statusBarOnTop

    /// Room between the display's top edge and a row when no status bar is above it.
    static let edgeMargin: CGFloat = 12

    func body(content: Content) -> some View {
        content.padding(.top, Self.topPadding(amount: amount, lifts: !compactOnly || sizeClass == .compact, statusBarOnTop: statusBarOnTop))
    }

    /// The row's top padding: up by `amount` under a status bar, a margin from the bare edge, nothing where the
    /// lift isn't drawn or there is nothing to lift.
    static func topPadding(amount: CGFloat, lifts: Bool, statusBarOnTop: Bool) -> CGFloat {
        guard lifts, amount > 0 else { return 0 }
        return statusBarOnTop ? -amount : edgeMargin
    }
}
