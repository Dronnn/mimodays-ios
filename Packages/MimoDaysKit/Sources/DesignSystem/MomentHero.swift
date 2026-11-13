import SwiftUI

/// What a hero shows: the moment's own picture, or a flat tone until there is one.
public enum HeroMedia {
    case placeholder
    case image(Image)
}

/// `Hero / Latest moment`: the photo in a hand-cut cream frame, a soft scrim and a handwritten caption,
/// with the tilted selfie window when the moment has one. Scales with the available width.
public struct MomentHero: View {
    let photo: HeroMedia
    let selfie: HeroMedia?
    let caption: Text

    public init(photo: HeroMedia, selfie: HeroMedia?, caption: Text) {
        self.photo = photo
        self.selfie = selfie
        self.caption = caption
    }

    public var body: some View {
        GeometryReader { proxy in
            let scale = proxy.size.width / Self.designSize.width
            ZStack(alignment: .bottomLeading) {
                HeroBlob()
                    .fill(ColorToken.mediaFrame.color)
                    .overlay { HeroBlob().stroke(ColorToken.mediaFrame.color, lineWidth: 9) }
                    .shadow(color: Color(hex: 0x4B2938).opacity(0.14), radius: 7, y: 4)
                Self.fill(photo, placeholder: 0x9C8573)
                    .overlay(alignment: .bottom) {
                        LinearGradient(
                            stops: [
                                .init(color: Self.scrim.opacity(0), location: 0),
                                .init(color: Self.scrim.opacity(0.18), location: 0.45),
                                .init(color: Self.scrim.opacity(0.54), location: 1),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: proxy.size.height * 0.6)
                    }
                    .clipShape(HeroBlob())
                caption
                    .textStyle(.hand)
                    .foregroundStyle(.white)
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .padding(.leading, 22 * scale)
                    .padding(.bottom, 42 * scale)
                if let selfie {
                    SelfieWindow(media: selfie)
                        .frame(width: 89 * scale, height: 110 * scale)
                        .position(x: proxy.size.width - 72.9 * scale, y: 37 * scale)
                }
            }
        }
        .aspectRatio(Self.designSize.width / Self.designSize.height, contentMode: .fit)
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isImage)
    }

    static let designSize = CGSize(width: 376.4, height: 273.6)
    private static let scrim = Color(hex: 0x221821)

    @ViewBuilder
    static func fill(_ media: HeroMedia, placeholder: UInt32) -> some View {
        switch media {
        case .placeholder: Color(hex: placeholder)
        case let .image(image): image.resizable().scaledToFill()
        }
    }
}

/// `Hero / PiP selfie`: cream rounded frame, tilted like every selfie window.
struct SelfieWindow: View {
    let media: HeroMedia

    var body: some View {
        GeometryReader { proxy in
            let scale = proxy.size.width / 89
            RoundedRectangle(cornerRadius: 19 * scale)
                .fill(ColorToken.mediaFrame.color)
                .shadow(color: Color(hex: 0x4B2938).opacity(0.2), radius: 6, y: 4)
                .overlay {
                    MomentHero.fill(media, placeholder: 0xB9A89A)
                        .clipShape(RoundedRectangle(cornerRadius: 15.5 * scale))
                        .padding(4 * scale)
                }
        }
        .rotationEffect(Size.selfieWindowTilt)
    }
}

public extension Color {
    /// Literal design colours that aren't tokens: photo placeholders, shadows, the brand gradient.
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
