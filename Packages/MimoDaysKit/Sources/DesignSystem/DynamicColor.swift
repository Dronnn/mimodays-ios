import SwiftUI
import UIKit

public extension Color {
    /// One colour in the light, another in the dark, from hex literals. The provider isn't isolated to the main
    /// actor: SwiftUI resolves colours on its render thread while it animates, and a provider made inside a view
    /// (main actor) trapped there when the home turned.
    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { traits in rgb(traits.userInterfaceStyle == .dark ? dark : light) })
    }
}

private func rgb(_ hex: UInt32) -> UIColor {
    UIColor(red: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}
