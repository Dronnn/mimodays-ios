import DesignSystem
import SwiftUI

/// One layer of a design illustration, drawn on a fixed canvas in design points.
enum ArtLayer {
    /// A vector template image covering the whole canvas.
    case shape(_ asset: String, _ fill: ArtFill, shadow: ArtShadow?)
    /// Live text, so it can be translated; placed by its centre, like in the design. A longer translation shrinks
    /// on its line to `width`: by default as wide as the picture allows around the centre.
    case text(_ content: ArtText, _ style: TextStyle, _ color: ColorToken, center: CGPoint, rotation: Double, width: CGFloat? = nil)
}

enum ArtFill {
    case token(ColorToken, opacity: Double = 1)
    /// Flat tone standing in for a photo until real images are added.
    case placeholder(UInt32)
    /// A photo filling the shape: drawn over `frame` (the shape's bounds, before `rotation` about its centre) and
    /// cut to the shape.
    case photo(String, frame: CGRect, rotation: Double = 0)
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
        case let .shape(asset, .photo(photo, frame, rotation), shadow):
            Image(photo, bundle: .module)
                .resizable()
                .scaledToFill()
                .frame(width: frame.width, height: frame.height)
                .clipped()
                .rotationEffect(.degrees(rotation))
                .position(x: frame.midX, y: frame.midY)
                .frame(width: size.width, height: size.height)
                .mask {
                    Image(asset, bundle: .module).resizable().frame(width: size.width, height: size.height)
                }
                .shadow(
                    color: Color(hex: shadow?.color ?? 0).opacity(shadow?.opacity ?? 0),
                    radius: shadow?.radius ?? 0, y: shadow?.y ?? 0
                )
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
        case let .text(content, style, color, center, rotation, width):
            content.text
                .textStyle(style)
                .foregroundStyle(color.color)
                // Light captions sit on photos; a soft shadow keeps them readable on bright ones.
                .shadow(color: .black.opacity(color == .textOnCoral ? 0.45 : 0), radius: 2, y: 1)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(maxWidth: width ?? 2 * min(center.x, size.width - center.x) - 8)
                .rotationEffect(.degrees(rotation))
                .position(center)
        }
    }

    private func style(for fill: ArtFill) -> AnyShapeStyle {
        switch fill {
        case let .token(token, opacity): AnyShapeStyle(token.color.opacity(opacity))
        case let .placeholder(hex): AnyShapeStyle(Color(hex: hex))
        case .photo: AnyShapeStyle(Color.clear)
        case .brandGradient: AnyShapeStyle(LinearGradient(colors: [Color(hex: 0xF27650), Color(hex: 0xE2582F)], startPoint: .top, endPoint: .bottom))
        }
    }
}
