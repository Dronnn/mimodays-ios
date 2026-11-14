import SwiftUI

/// `Button / Primary`: hand-cut coral shape, Fraunces label, soft coral shadow. Full width, 54 pt tall.
public struct PrimaryButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .textStyle(.buttonPrimary)
            .foregroundStyle(ColorToken.textOnCoral.color)
            .multilineTextAlignment(.center)
            .padding(.horizontal, Spacing.screenMargin)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background {
                LinearGradient.actionCoral
                    .mask { Icon.shapeButton.image.resizable() }
                    .shadow(color: ColorToken.textLink.color.opacity(0.25), radius: 6, y: 4)
            }
            .opacity(configuration.isPressed ? 0.85 : 1)
            .contentShape(Rectangle())
    }
}

/// `Button / Text`: coral Nunito label, 44 pt tall hit area.
public struct TextButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .textStyle(.control)
            .foregroundStyle(ColorToken.textLink.color)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: Size.minimumTapTarget)
            .opacity(configuration.isPressed ? 0.6 : 1)
            .contentShape(Rectangle())
    }
}

/// `Button / Destructive`: dark coral words on the hand-cut peach shape, 52 pt tall (M07, M15, S08).
public struct DestructiveButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .textStyle(.rowTitle)
            .foregroundStyle(ColorToken.textDestructive.color)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background { ColorToken.accentPeach.color.mask { Icon.shapeButton.image.resizable() } }
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Rectangle())
    }
}

public extension ButtonStyle where Self == DestructiveButtonStyle {
    static var destructive: DestructiveButtonStyle { DestructiveButtonStyle() }
}

public extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

public extension ButtonStyle where Self == TextButtonStyle {
    static var text: TextButtonStyle { TextButtonStyle() }
}
