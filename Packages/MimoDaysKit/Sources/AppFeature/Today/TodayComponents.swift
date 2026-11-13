import DesignSystem
import SwiftUI

/// `Surprise / Ribbon` (T02-T07): the mint oval with an apricot star. It hugs its words; with an action
/// (Open, Resume, Turn on) it spans the width and the action sits on a cream pill at the end.
struct SurpriseRibbon: View {
    let status: SurpriseStatus
    let now: Date
    let action: () -> Void
    @Environment(\.calendar) private var calendar

    var body: some View {
        HStack(spacing: 10) {
            Icon.markStarSmall.image
                .resizable()
                .frame(width: 16, height: 16.5)
                .foregroundStyle(ColorToken.accentApricot.color)
                .accessibilityHidden(true)
            Text(message)
                .textStyle(.hand)
                .foregroundStyle(ColorToken.textPrimary.color)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle {
                Spacer(minLength: 4)
                Button(action: action) {
                    Text(actionTitle)
                        .textStyle(.ribbonAction)
                        .foregroundStyle(ColorToken.textLink.color)
                        .padding(.horizontal, 22)
                        .frame(minHeight: 30)
                        .background(ReviewChipBlob().fill(ColorToken.surfaceCard.color))
                        .padding(.vertical, 7)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.vertical, -7)
                .accessibilityIdentifier("today.ribbon.action")
            }
        }
        .padding(.leading, actionTitle == nil ? 21 : 16)
        .padding(.trailing, actionTitle == nil ? 25 : 12)
        .padding(.vertical, 5)
        .frame(minHeight: actionTitle == nil ? 32 : 40)
        .frame(maxWidth: actionTitle == nil ? nil : .infinity)
        .background(RibbonBlob().fill(ColorToken.accentMint.color))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("today.ribbon")
    }

    private var message: LocalizedStringResource {
        switch status {
        case .onItsWay: resource("Your next surprise is on its way")
        case .ready: resource("A surprise moment is ready")
        case .passed: resource("That surprise has passed. Catch a moment anyway?")
        case .paused(nil): resource("Surprises are paused")
        case let .paused(until?): pausedUntil(until)
        case .off: resource("Turn on little surprises")
        }
    }

    private var actionTitle: LocalizedStringResource? {
        switch status {
        case .ready: resource("Open")
        case .paused: resource("Resume")
        case .off: resource("Turn on")
        case .onItsWay, .passed: nil
        }
    }

    /// The pause ends at the start of `until`: "tomorrow", a weekday within the week, or a date.
    private func pausedUntil(_ until: Date) -> LocalizedStringResource {
        let today = calendar.startOfDay(for: now)
        let days = calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: until)).day ?? 0
        if days <= 1 { return resource("Surprises are paused until tomorrow") }
        let day = days < 7
            ? until.formatted(.dateTime.weekday(.wide))
            : until.formatted(.dateTime.month(.abbreviated).day())
        return LocalizedStringResource("Surprises are paused until \(day)", bundle: .atURL(Bundle.module.bundleURL))
    }

    private func resource(_ key: String.LocalizationValue) -> LocalizedStringResource {
        LocalizedStringResource(key, bundle: .atURL(Bundle.module.bundleURL))
    }
}

/// `Recent / Thumb`: a moment's thumbnail in one of four hand-cut shapes.
struct StripTile: View {
    struct Style {
        var shape: AnyShape
        var size: CGSize
        var lift: CGFloat
    }

    static let styles = [
        Style(shape: AnyShape(StripBlobA()), size: CGSize(width: 98.6, height: 84.4), lift: 0),
        Style(shape: AnyShape(StripBlobB()), size: CGSize(width: 89.9, height: 81.1), lift: 0),
        Style(shape: AnyShape(StripBlobC()), size: CGSize(width: 98.4, height: 83.6), lift: 1),
        Style(shape: AnyShape(StripBlobD()), size: CGSize(width: 86, height: 84.5), lift: 2),
    ]

    let image: UIImage?
    let style: Style

    var body: some View {
        Color(hex: 0xC9B8AA)
            .overlay {
                if let image { Image(uiImage: image).resizable().scaledToFill() }
            }
            .frame(width: style.size.width, height: style.size.height)
            .clipShape(style.shape)
            .background(style.shape.fill(Color(hex: 0xC9B8AA)).shadow(color: Color(hex: 0x4B2938).opacity(0.1), radius: 3, y: 2))
            .offset(y: -style.lift)
            .accessibilityElement()
            .accessibilityAddTraits(.isImage)
    }
}

/// T06: an earlier year's moment in the hero's cream frame, with "One year ago · 3 moments".
struct OnThisDayCard: View {
    let image: UIImage?
    let caption: Text

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            HeroBlob()
                .fill(ColorToken.mediaFrame.color)
                .overlay { HeroBlob().stroke(ColorToken.mediaFrame.color, lineWidth: 9) }
                .shadow(color: Color(hex: 0x4B2938).opacity(0.14), radius: 7, y: 4)
            Color(hex: 0x9C8573)
                .overlay {
                    if let image { Image(uiImage: image).resizable().scaledToFill() }
                }
                .overlay(alignment: .bottom) {
                    LinearGradient(colors: [.clear, Color(hex: 0x221821).opacity(0.5)], startPoint: .top, endPoint: .bottom)
                        .frame(maxHeight: .infinity)
                        .padding(.top, 60)
                }
                .clipShape(HeroBlob())
            caption
                .textStyle(.hand)
                .foregroundStyle(.white)
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .padding(.leading, 22)
                .padding(.bottom, 28)
        }
        .aspectRatio(362 / 200, contentMode: .fit)
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityElement(children: .combine)
    }
}
