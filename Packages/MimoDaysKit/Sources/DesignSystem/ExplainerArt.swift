import SwiftUI

/// `Explainer / Art`: a soft blob with a plum line glyph, an apricot star and coral ticks (150×140).
/// The blob is peach on permission explainers, mint for surprises and chip-coloured when reminders are off.
public struct ExplainerArt: View {
    let glyph: Icon
    let blob: ColorToken

    public init(glyph: Icon, blob: ColorToken = .accentPeach) {
        self.glyph = glyph
        self.blob = blob
    }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            layer(.artBlob, blob)
            layer(.markStar, .accentApricot)
            layer(.markTicks, .accentCoralMark)
            glyph.image
                .resizable()
                .scaledToFit()
                .frame(width: 56, height: 56)
                .foregroundStyle(ColorToken.textPrimary.color)
                .offset(x: 47, y: 44)
        }
        .frame(width: 150, height: 140)
        .accessibilityHidden(true)
    }

    private func layer(_ icon: Icon, _ color: ColorToken) -> some View {
        icon.image.resizable().frame(width: 150, height: 140).foregroundStyle(color.color)
    }
}
