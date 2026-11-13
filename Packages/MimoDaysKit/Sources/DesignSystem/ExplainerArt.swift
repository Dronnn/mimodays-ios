import SwiftUI

/// `Explainer / Art`: peach blob with a plum line glyph, an apricot star and coral ticks (150×140).
public struct ExplainerArt: View {
    let glyph: Icon

    public init(glyph: Icon) {
        self.glyph = glyph
    }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            layer(.artBlob, .accentPeach)
            layer(.markStar, .accentApricot)
            layer(.markTicks, .accentCoralMark)
            glyph.image
                .resizable()
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
