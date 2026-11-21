import Core
import DesignSystem
import SwiftUI

/// `Surprise / Ribbon` (T02-T07): the mint oval with an apricot star. It hugs its words; with an action
/// (Open, Resume, Turn on), or T04's long line, it spans the width, and an action sits on a cream pill at the end.
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
            VStack(alignment: .leading, spacing: 0) {
                Text(message)
                    .textStyle(isLong ? .handSmall : .hand)
                if let detail {
                    Text(detail).textStyle(.handSmall)
                }
            }
            .foregroundStyle(ColorToken.textPrimary.color)
            .fixedSize(horizontal: false, vertical: true)
            // The words fill the row up to the action, which never wraps.
            .frame(maxWidth: isWide ? .infinity : nil, alignment: .leading)
            if let actionTitle {
                Button(action: action) {
                    Text(actionTitle)
                        .textStyle(.ribbonAction)
                        .foregroundStyle(ColorToken.textLink.color)
                        .fixedSize()
                        .padding(.horizontal, 16)
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
        .padding(.leading, isWide ? 16 : 21)
        .padding(.trailing, actionTitle == nil ? (isWide ? 16 : 25) : 12)
        .padding(.vertical, 5)
        .frame(minHeight: isWide ? 40 : 32)
        .frame(maxWidth: isWide ? .infinity : nil, alignment: .leading)
        .background(RibbonBlob().fill(ColorToken.accentMint.color))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("today.ribbon")
    }

    private var isWide: Bool { actionTitle != nil || isLong || detail != nil }

    /// A whole sentence rather than a few words: smaller, across the width.
    private var isLong: Bool {
        switch status {
        case .passed, .retryFailed: true
        default: false
        }
    }

    /// P8.7: under "A little later".
    private var detail: LocalizedStringResource? {
        status == .later ? resource("Your surprise will be back today.") : nil
    }

    private var message: LocalizedStringResource {
        switch status {
        case .onItsWay: resource("Your next surprise is on its way")
        case .ready: resource("A surprise moment is ready")
        case .passed: resource("That surprise has passed. Catch a moment anyway?")
        case .paused(nil): resource("Surprises are paused")
        case let .paused(until?): pausedUntil(until)
        case .off: resource("Turn on little surprises")
        case .later: resource("A little later")
        case .retryFailed(.noTime): resource("No time left for another surprise today.")
        case .retryFailed(.failed): resource("Couldn't set the reminder.")
        }
    }

    private var actionTitle: LocalizedStringResource? {
        switch status {
        case .ready: resource("Open")
        case .paused: resource("Resume")
        case .off: resource("Turn on")
        case .onItsWay, .passed, .later, .retryFailed: nil
        }
    }

    /// The pause ends at the start of `until`: "tomorrow", a weekday within the week, or a date.
    private func pausedUntil(_ until: Date) -> LocalizedStringResource {
        let today = calendar.startOfDay(for: now)
        let days = calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: until)).day ?? 0
        if days <= 1 { return resource("Surprises are paused until tomorrow") }
        let day = days < 7
            ? until.formatted(.dateTime.weekday(.wide).locale(AppLanguage.shared.locale))
            : until.formatted(.dateTime.month(.abbreviated).day().locale(AppLanguage.shared.locale))
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

    /// One of the four hand-cut shapes, picked from `seed` so a tile keeps its shape (Andrew, 2026-11-16: Memories and
    /// the iPad's month grid are cut like the strip, never plain rounded squares).
    static func shape(_ seed: Int) -> AnyShape {
        styles[(seed & Int.max) % styles.count].shape
    }

    /// By the moment's capture time, mixed so neighbours differ: the same on every launch and in every test.
    static func shape(_ captured: Date) -> AnyShape {
        shape(Int(captured.timeIntervalSince1970) &* 2_654_435_761 >> 16)
    }

    /// The strip's soft shadow under a hand-cut tile.
    static func shadow(_ shape: AnyShape) -> some View {
        shape.fill(Color(hex: 0xC9B8AA)).shadow(color: Color(hex: 0x4B2938).opacity(0.1), radius: 3, y: 2)
    }

    let image: UIImage?
    let style: Style
    /// H.9: a video tile plays.
    var id: UUID?
    var isVideo = false
    /// P8.11: a written moment's words on paper instead of a picture.
    var paper: String??

    var body: some View {
        Color(hex: 0xC9B8AA)
            .overlay {
                if let paper {
                    PaperTileFace(excerpt: paper.map { String($0.prefix(TextMoment.tileExcerptLimit)) })
                } else if let image {
                    Image(uiImage: image).filling()
                }
            }
            .frame(width: style.size.width, height: style.size.height)
            .tileMotion(id ?? UUID(), isVideo: isVideo && id != nil, still: image)
            .clipShape(style.shape)
            .background(Self.shadow(style.shape))
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
                    if let image { Image(uiImage: image).filling() }
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
