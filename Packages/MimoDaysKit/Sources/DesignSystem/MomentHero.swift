import SwiftUI

/// What a hero shows: the moment's own picture, or a flat tone until there is one.
public enum HeroMedia {
    case placeholder
    case image(Image)
}

/// `Hero / Latest moment`: the photo in a hand-cut cream frame, a soft scrim and a handwritten caption,
/// with the tilted selfie window when the moment has one. Scales with the available width.
/// Today adds the place above the time and, for a surprise, the mint `Hero / Surprise tag` (T03).
public struct MomentHero: View {
    let photo: HeroMedia
    let selfie: HeroMedia?
    let caption: Text
    let place: Text?
    let tag: Text?
    @Environment(\.colorSchemeContrast) private var contrast

    public init(photo: HeroMedia, selfie: HeroMedia?, caption: Text, place: Text? = nil, tag: Text? = nil) {
        self.photo = photo
        self.selfie = selfie
        self.caption = caption
        self.place = place
        self.tag = tag
    }

    public var body: some View {
        GeometryReader { proxy in
            let scale = proxy.size.width / Self.designSize.width
            // Increase Contrast: a darker scrim under the white caption (A07).
            let scrim = contrast == .increased ? 1.5 : 1.0
            ZStack(alignment: .bottomLeading) {
                HeroBlob()
                    .fill(ColorToken.mediaFrame.color)
                    .overlay { HeroBlob().stroke(ColorToken.mediaFrame.color, lineWidth: 9) }
                    .shadow(color: Color(hex: 0x4B2938).opacity(0.14), radius: 7, y: 4)
                Self.fill(photo, placeholder: 0x9C8573)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .overlay(alignment: .bottom) {
                        LinearGradient(
                            stops: [
                                .init(color: Self.scrim.opacity(0), location: 0),
                                .init(color: Self.scrim.opacity(0.18 * scrim), location: 0.45),
                                .init(color: Self.scrim.opacity(0.54 * scrim), location: 1),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: proxy.size.height * 0.6)
                    }
                    .clipShape(HeroBlob())
                captionBlock
                    .foregroundStyle(.white)
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .padding(.leading, 22 * scale)
                    .padding(.bottom, 42 * scale)
                if let selfie {
                    SelfieWindow(media: selfie)
                        .frame(width: 89 * scale, height: SelfieWindowStyle.height(forWidth: 89 * scale))
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

    /// The tag, the pin and place, then the time a little in from the pin (T02/T03).
    @ViewBuilder
    private var captionBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let tag {
                HStack(spacing: 6) {
                    Icon.markStarSmall.image
                        .resizable()
                        .frame(width: 13, height: 13)
                        .foregroundStyle(ColorToken.accentCoralMark.color)
                    tag
                        .textStyle(.heroTag)
                        .foregroundStyle(ColorToken.textPrimary.color)
                }
                .padding(.leading, 11)
                .padding(.trailing, 12)
                .frame(minHeight: 28)
                .background(RibbonBlob().fill(ColorToken.accentMint.color))
                .padding(.bottom, 5)
            }
            if let place {
                HStack(spacing: 6) {
                    Icon.glyphPinSolid.image
                        .resizable()
                        .frame(width: 14, height: 18)
                    place.textStyle(.hand)
                }
                caption
                    .textStyle(.heroTime)
                    .padding(.leading, 13)
                    .padding(.top, 2)
            } else {
                caption.textStyle(.hand)
            }
        }
    }

    @ViewBuilder
    static func fill(_ media: HeroMedia, placeholder: UInt32) -> some View {
        switch media {
        case .placeholder: Color(hex: placeholder)
        case let .image(image): image.filling()
        }
    }
}

/// T01: the hero's frame before there is a moment. No made-up memory, just where the two pictures will go:
/// "what you see" and the tilted selfie window, "you".
public struct EmptyMomentHero: View {
    let title: Text
    let scene: Text
    let selfie: Text

    public init(title: Text, scene: Text, selfie: Text) {
        self.title = title
        self.scene = scene
        self.selfie = selfie
    }

    public var body: some View {
        GeometryReader { proxy in
            let scale = proxy.size.width / MomentHero.designSize.width
            ZStack(alignment: .topLeading) {
                HeroBlob()
                    .fill(ColorToken.surfaceChip.color)
                    .overlay { HeroBlob().stroke(ColorToken.mediaFrame.color, lineWidth: 9) }
                    .shadow(color: Color(hex: 0x4B2938).opacity(0.14), radius: 7, y: 4)
                title
                    .textStyle(.emptyHeroTitle)
                    .foregroundStyle(ColorToken.textPrimary.color)
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .multilineTextAlignment(.center)
                    .frame(width: proxy.size.width - 40 * scale)
                    .position(x: proxy.size.width / 2, y: 27 * scale)
                StripBlobA()
                    .fill(ColorToken.textPrimary.color.opacity(0.06))
                    .overlay { SceneGlyph().stroke(Self.glyph, style: Self.line).frame(width: 38, height: 26) }
                    .frame(width: 132 * scale, height: 112 * scale)
                    .position(x: 150 * scale, y: 106 * scale)
                SelfieWindow(media: .placeholder)
                    .overlay { PersonGlyph().stroke(Self.glyph, style: Self.line).frame(width: 26, height: 34).rotationEffect(Size.selfieWindowTilt) }
                    .frame(width: 89 * scale, height: SelfieWindowStyle.height(forWidth: 89 * scale))
                    .position(x: 237.5 * scale, y: 99 * scale)
                scene
                    .textStyle(.emptyHeroLabel)
                    .foregroundStyle(ColorToken.textSecondary.color)
                    .dynamicTypeSize(...DynamicTypeSize.xLarge)
                    .fixedSize()
                    .position(x: 150 * scale, y: 175 * scale)
                selfie
                    .textStyle(.emptyHeroLabel)
                    .foregroundStyle(ColorToken.textSecondary.color)
                    .dynamicTypeSize(...DynamicTypeSize.xLarge)
                    .fixedSize()
                    .position(x: 237.5 * scale, y: 165 * scale)
            }
        }
        .aspectRatio(MomentHero.designSize.width / MomentHero.designSize.height, contentMode: .fit)
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
    }

    private static let glyph = Color(hex: 0xA8917F)
    private static let line = StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round)
}

/// `Empty / Scene glyph`: a sun over two hills.
private struct SceneGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width / 38, h = rect.height / 26
        path.addEllipse(in: CGRect(x: rect.minX + 23.5 * w, y: rect.minY, width: 9 * w, height: 9 * h))
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + 26 * h))
        path.addLine(to: CGPoint(x: rect.minX + 12 * w, y: rect.minY + 10 * h))
        path.addLine(to: CGPoint(x: rect.minX + 20 * w, y: rect.minY + 19 * h))
        path.addLine(to: CGPoint(x: rect.minX + 25 * w, y: rect.minY + 13 * h))
        path.addLine(to: CGPoint(x: rect.minX + 38 * w, y: rect.minY + 26 * h))
        path.closeSubpath()
        return path
    }
}

/// `Empty / Selfie glyph`: a head and shoulders.
private struct PersonGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width / 26, h = rect.height / 34
        path.addEllipse(in: CGRect(x: rect.minX + 5 * w, y: rect.minY, width: 16 * w, height: 16 * h))
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + 34 * h))
        path.addCurve(
            to: CGPoint(x: rect.minX + 26 * w, y: rect.minY + 33 * h),
            control1: CGPoint(x: rect.minX + 2 * w, y: rect.minY + 20 * h),
            control2: CGPoint(x: rect.minX + 23 * w, y: rect.minY + 19 * h)
        )
        return path
    }
}

/// The selfie window's look. The camera's window (C01/C04) is the reference; the review, the player, every
/// preview and the exported files draw the same window (Andrew, 2026-11-14). Metrics are for the 112 × 150
/// medium window and scale with the width, so any size is the same window.
public enum SelfieWindowStyle {
    public static let size = CGSize(width: 112, height: 150)
    public static let cornerRadius: CGFloat = 22
    public static let border: CGFloat = 4
    public static let innerCornerRadius: CGFloat = 18
    public static let shadowOpacity = 0.22
    /// Blur radius as Core Graphics takes it; SwiftUI's shadow radius is half of it.
    public static let shadowBlur: CGFloat = 14
    public static let shadowY: CGFloat = 4
    public static var tilt: Angle { Size.selfieWindowTilt }
    /// One cream in light and dark, so the window on screen and in an exported file is the same.
    public static let frameHex: UInt32 = 0xFBF6EF
    public static var frameColor: Color { Color(hex: frameHex) }

    /// The window's height for a width.
    public static func height(forWidth width: CGFloat) -> CGFloat {
        width * size.height / size.width
    }
}

/// The selfie window: a cream frame with the picture clipped inside it, never over it. Takes the window's
/// shape at the width it is given; `tilted` false when the caller tilts it together with something else.
public struct SelfieFrame<Content: View>: View {
    let placeholder: Color
    let tilted: Bool
    let content: Content

    public init(placeholder: Color = Color(hex: 0xB9A89A), tilted: Bool = true, @ViewBuilder content: () -> Content) {
        self.placeholder = placeholder
        self.tilted = tilted
        self.content = content()
    }

    public var body: some View {
        GeometryReader { proxy in
            let k = proxy.size.width / SelfieWindowStyle.size.width
            RoundedRectangle(cornerRadius: SelfieWindowStyle.cornerRadius * k, style: .continuous)
                .fill(SelfieWindowStyle.frameColor)
                .shadow(
                    color: .black.opacity(SelfieWindowStyle.shadowOpacity),
                    radius: SelfieWindowStyle.shadowBlur / 2 * k, y: SelfieWindowStyle.shadowY * k
                )
                .overlay {
                    // The colour takes the opening's size; the picture fills it and is cut to it.
                    placeholder
                        .overlay { content }
                        .clipShape(RoundedRectangle(cornerRadius: SelfieWindowStyle.innerCornerRadius * k, style: .continuous))
                        .padding(SelfieWindowStyle.border * k)
                }
        }
        .aspectRatio(SelfieWindowStyle.size.width / SelfieWindowStyle.size.height, contentMode: .fit)
        .rotationEffect(tilted ? SelfieWindowStyle.tilt : .zero)
    }
}

/// `Hero / PiP selfie`: the selfie window with a still in it, at the width it is given.
public struct SelfieWindow: View {
    let media: HeroMedia

    public init(media: HeroMedia) {
        self.media = media
    }

    public var body: some View {
        SelfieFrame {
            if case let .image(image) = media {
                image.filling()
            }
        }
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
