import DesignSystem
import SwiftUI

/// One layer of a design illustration, drawn on a fixed canvas in design points.
enum ArtLayer {
    /// A vector template image covering the whole canvas.
    case shape(_ asset: String, _ fill: ArtFill, shadow: ArtShadow?)
    /// Live text, so it can be translated; placed by its centre, like in the design.
    case text(_ content: ArtText, _ style: TextStyle, _ color: ColorToken, center: CGPoint, rotation: Double)
}

enum ArtFill {
    case token(ColorToken, opacity: Double = 1)
    /// Flat tone standing in for a photo until real images are added.
    case placeholder(UInt32)
    /// The app icon's coral gradient.
    case brandGradient
}

enum ArtText {
    case localized(LocalizedStringResource)
    /// Brand text that is never translated.
    case verbatim(String)

    var text: Text {
        switch self {
        case let .localized(resource): Text(resource)
        case let .verbatim(string): Text(verbatim: string)
        }
    }
}

struct ArtShadow {
    var color: UInt32
    var opacity: Double
    var radius: CGFloat
    var y: CGFloat
}

/// Draws layers at the design size and scales the whole picture to the available width.
/// Decorative: hidden from VoiceOver, never mirrored, and its text doesn't follow Dynamic Type.
struct ArtCanvas: View {
    let layers: [ArtLayer]
    var size = CGSize(width: 362, height: 360)

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                ForEach(layers.indices, id: \.self) { index in
                    layer(layers[index])
                }
            }
            .frame(width: size.width, height: size.height)
            .scaleEffect(proxy.size.width / size.width, anchor: .topLeading)
        }
        .aspectRatio(size.width / size.height, contentMode: .fit)
        .frame(maxWidth: size.width)
        .environment(\.layoutDirection, .leftToRight)
        .environment(\.dynamicTypeSize, .large)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func layer(_ layer: ArtLayer) -> some View {
        switch layer {
        case let .shape(asset, fill, shadow):
            Image(asset, bundle: .module)
                .renderingMode(.template)
                .resizable()
                .frame(width: size.width, height: size.height)
                .foregroundStyle(style(for: fill))
                .shadow(
                    color: Color(hex: shadow?.color ?? 0).opacity(shadow?.opacity ?? 0),
                    radius: shadow?.radius ?? 0, y: shadow?.y ?? 0
                )
        case let .text(content, style, color, center, rotation):
            content.text
                .textStyle(style)
                .foregroundStyle(color.color)
                .fixedSize()
                .rotationEffect(.degrees(rotation))
                .position(center)
        }
    }

    private func style(for fill: ArtFill) -> AnyShapeStyle {
        switch fill {
        case let .token(token, opacity): AnyShapeStyle(token.color.opacity(opacity))
        case let .placeholder(hex): AnyShapeStyle(Color(hex: hex))
        case .brandGradient: AnyShapeStyle(LinearGradient(colors: [Color(hex: 0xF27650), Color(hex: 0xE2582F)], startPoint: .top, endPoint: .bottom))
        }
    }
}

extension Color {
    /// Literal design colours that aren't tokens: photo placeholders, shadows, the brand gradient.
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
