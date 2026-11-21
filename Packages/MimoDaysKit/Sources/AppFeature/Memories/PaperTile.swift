import DesignSystem
import SwiftUI

/// P8.11 II06: a written moment as a tile: paper with its first words in the hand-written face and a coral "T".
/// Without words (not read yet, or a tile too small for them) only the paper and the glyph.
struct PaperTileFace: View {
    var excerpt: String?
    var glyphSize: CGFloat = 16
    /// A day's wide card: the larger hand and more room from its hand-cut edge.
    var isLarge = false

    var body: some View {
        let inset: CGFloat = isLarge ? 28 : 12
        ColorToken.surfaceCard.color
            .overlay(alignment: .topLeading) {
                if let excerpt {
                    Text(excerpt)
                        .textStyle(isLarge ? .dayCaption : .paperTile)
                        .foregroundStyle(ColorToken.textPrimary.color)
                        .padding(.horizontal, inset)
                        .padding(.top, inset + 2)
                        .padding(.bottom, glyphSize + inset + 2)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .minimumScaleFactor(0.8)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                Icon.glyphText.image
                    .resizable()
                    .frame(width: glyphSize, height: glyphSize)
                    .foregroundStyle(ColorToken.actionCoral.color)
                    .padding(isLarge ? 26 : 10)
            }
            .accessibilityHidden(true)
    }
}

/// P8.11: Today's hero for a written moment: paper with the caption in coral and the first words, leaving the bottom
/// to the hero's own place and time.
struct PaperHero: View {
    var title: String?
    var excerpt: String?

    var body: some View {
        ColorToken.surfaceCard.color
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 6) {
                    if let title {
                        Text(title)
                            .textStyle(.viewerPlace)
                            .foregroundStyle(ColorToken.textLink.color)
                            .lineLimit(1)
                    }
                    if let excerpt {
                        Text(excerpt)
                            .textStyle(.dayCaption)
                            .foregroundStyle(ColorToken.textPrimary.color)
                            .lineLimit(3)
                    }
                }
                .padding(.horizontal, 26)
                .padding(.top, 30)
                .padding(.trailing, 90)
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            }
            .accessibilityHidden(true)
    }
}
