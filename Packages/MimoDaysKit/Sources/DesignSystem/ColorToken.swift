import SwiftUI

/// Semantic colours from docs/design-tokens.md. Each has a light and a dark value in Colors.xcassets.
public enum ColorToken: String, CaseIterable, Sendable {
    case canvas
    case canvasSidebar
    case surfaceCard
    case surfaceSheet
    case surfaceChip
    case accentPeach
    case accentMint
    /// Decoration only (star marks).
    case accentApricot
    /// Decoration only (hatch marks).
    case accentSage
    /// Decoration only (coral tick marks).
    case accentCoralMark
    case textPrimary
    case textSecondary
    /// Explainer and long-form body copy.
    case textBody
    /// Row details, e.g. the time in a settings row.
    case textTertiary
    case textLink
    /// Words on a destructive button (`Button / Destructive`): darker than the link, readable on peach.
    case textDestructive
    case textOnCoral
    case actionCoral
    case actionCoralGradientStart
    case actionCoralGradientEnd
    case borderSubtle
    /// Hairlines between rows in a card.
    case separator
    /// Progress dots not reached yet.
    case indicatorInactive
    /// PiP / selfie frame; stays light in dark mode.
    case mediaFrame
    /// 45 % scrim behind text on photos.
    case mediaScrim

    public var color: Color { Color(rawValue, bundle: .module) }
}

public extension Color {
    init(_ token: ColorToken) {
        self = token.color
    }
}

public extension LinearGradient {
    /// Fill of primary buttons and the capture disk.
    static let actionCoral = LinearGradient(
        colors: [ColorToken.actionCoralGradientStart.color, ColorToken.actionCoralGradientEnd.color],
        startPoint: .top,
        endPoint: .bottom
    )
}
