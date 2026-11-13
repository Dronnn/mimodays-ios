import SwiftUI

/// Spacing, radius and size tokens from docs/design-tokens.md.
public enum Spacing {
    public static let screenMargin: CGFloat = 20
    public static let cardMargin: CGFloat = 16
    public static let sectionGap: CGFloat = 24
}

public enum Radius {
    public static let card: CGFloat = 22
    public static let sheet: CGFloat = 28
    public static let field: CGFloat = 14
    public static let iconBackground: CGFloat = 12
}

public enum Size {
    public static let rowHeight: CGFloat = 52
    public static let rowHeightWithSubtitle: CGFloat = 64
    public static let iconBackground: CGFloat = 36
    public static let iconBackgroundLargeText: CGFloat = 48
    /// Minimum hit area for any control, even when drawn smaller.
    public static let minimumTapTarget: CGFloat = 44
    public static let captureButton: CGFloat = 80
    /// The selfie window is tilted the same way everywhere it appears.
    public static let selfieWindowTilt: Angle = .degrees(-5.4)
}

public enum Elevation: Sendable {
    case photoFrame
    case sheet
    case notificationBanner

    var color: Color {
        switch self {
        case .photoFrame: Color(red: 0x4A / 255, green: 0x27 / 255, blue: 0x34 / 255).opacity(0.14)
        case .sheet: Color(red: 0x2A / 255, green: 0x1B / 255, blue: 0x21 / 255).opacity(0.25)
        case .notificationBanner: Color(red: 0x4A / 255, green: 0x27 / 255, blue: 0x34 / 255).opacity(0.16)
        }
    }

    var radius: CGFloat {
        switch self {
        case .photoFrame: 9
        case .sheet: 20
        case .notificationBanner: 12
        }
    }

    var y: CGFloat {
        switch self {
        case .photoFrame: 6
        case .sheet: 12
        case .notificationBanner: 8
        }
    }
}

public extension View {
    /// Design shadow. Blur values from the tokens are halved: SwiftUI's radius is about half a design blur.
    func elevation(_ elevation: Elevation) -> some View {
        shadow(color: elevation.color, radius: elevation.radius, x: 0, y: elevation.y)
    }
}
