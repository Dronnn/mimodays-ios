import DesignSystem
import SwiftUI
import WidgetKit

/// §V6 type: Nunito headings and pills, Fraunces titles, Inter details.
enum WidgetStyle {
    static let heading = TextStyle(.body, size: 13, weight: 800, relativeTo: .caption1, maximumScale: 1.2)
    static let title = TextStyle(.heading, size: 17, weight: 600, relativeTo: .headline, maximumScale: 1.2)
    static let titleLarge = TextStyle(.heading, size: 19, weight: 600, relativeTo: .headline, maximumScale: 1.2)
    static let brand = TextStyle(.heading, size: 20, weight: 600, relativeTo: .title3, maximumScale: 1.2)
    static let detail = TextStyle(.label, size: 12, weight: 400, relativeTo: .caption1, maximumScale: 1.2)
    static let kind = TextStyle(.label, size: 13, weight: 400, relativeTo: .footnote, maximumScale: 1.2)
    static let pill = TextStyle(.body, size: 13, weight: 800, relativeTo: .caption1, maximumScale: 1.1)
    static let year = TextStyle(.body, size: 12, weight: 700, relativeTo: .caption2, maximumScale: 1.2)
}

public extension View {
    /// The widgets speak the language MimoDays shows, in the faces for its alphabet.
    func widgetLanguage(_ code: String) -> some View {
        let locale = Locale(identifier: code)
        return environment(\.locale, locale)
            .environment(\.layoutDirection, locale.language.characterDirection == .rightToLeft ? .rightToLeft : .leftToRight)
            .environment(\.typefaces, Typefaces(language: code))
    }

    /// The widget's own background: the MimoDays card surface, edge to edge.
    func widgetCard() -> some View {
        containerBackground(for: .widget) { ColorToken.surfaceCard.color }
    }
}

/// The Another control, made by the widget extension (its button runs an intent there); plain in tests.
public typealias AnotherButton = (_ label: AnyView) -> AnyView

// MARK: On this day

/// AA01/AA02: On this day, small and medium.
public struct OnThisDayWidgetView: View {
    let content: WidgetContent.OnThisDay
    let isMedium: Bool
    let image: UIImage?
    @Environment(\.locale) private var locale

    public init(content: WidgetContent.OnThisDay, isMedium: Bool, image: UIImage?) {
        self.content = content
        self.isMedium = isMedium
        self.image = image
    }

    public var body: some View {
        switch content {
        case .placeholder:
            PlainTile(heading: Text("On this day", bundle: .module))
        case .locked:
            LockedTile()
        case .empty:
            WordsTile(heading: Text("On this day", bundle: .module), star: false) {
                Text("Nothing on this day yet", bundle: .module).textStyle(WidgetStyle.title)
            } actions: {
                Pill(Text("Open MimoDays", bundle: .module), isPrimary: false)
            }
            .widgetURL(WidgetLink.app)
        case let .memory(day):
            memory(day)
                .widgetURL(WidgetLink.onThisDay)
        }
    }

    @ViewBuilder
    private func memory(_ day: WidgetPayload.Day) -> some View {
        let title = Text("\(day.count) moments from \(DayText(key: day.cover.day, style: .short).string(locale))", bundle: .module)
        if let image {
            if isMedium {
                HStack(spacing: 14) {
                    PhotoTile(image: image).overlay(alignment: .bottomTrailing) { YearLabel(key: day.cover.day) }
                        .frame(width: 150)
                    VStack(alignment: .leading, spacing: 8) {
                        Heading(Text("On this day", bundle: .module))
                        title.textStyle(WidgetStyle.title).privacySensitive()
                        Spacer(minLength: 0)
                        Pill(Text("Open memory", bundle: .module), isPrimary: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(12)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Heading(Text("On this day", bundle: .module))
                    PhotoTile(image: image).overlay(alignment: .bottomTrailing) { YearLabel(key: day.cover.day) }
                        .accessibilityLabel(title)
                }
                .padding(12)
            }
        } else {
            WordsTile(heading: Text("On this day", bundle: .module), star: true) {
                title.textStyle(WidgetStyle.title).privacySensitive()
            } actions: {
                Pill(Text("Open memory", bundle: .module), isPrimary: true)
            }
        }
    }
}

// MARK: Random memory

/// AA01/AA02: Random memory, small and medium; Another picks a new one in the widget.
public struct RandomMemoryWidgetView: View {
    let content: WidgetContent.Random
    let isMedium: Bool
    let showsPhotos: Bool
    let image: UIImage?
    let another: AnotherButton
    @Environment(\.locale) private var locale

    public init(content: WidgetContent.Random, isMedium: Bool, showsPhotos: Bool, image: UIImage?, another: @escaping AnotherButton) {
        self.content = content
        self.isMedium = isMedium
        self.showsPhotos = showsPhotos
        self.image = image
        self.another = another
    }

    public var body: some View {
        switch content {
        case .placeholder:
            PlainTile(heading: Text("Random memory", bundle: .module))
        case .locked:
            LockedTile()
        case .empty:
            WordsTile(heading: Text("Random memory", bundle: .module), star: false) {
                Text("No memories yet", bundle: .module).textStyle(WidgetStyle.title)
            } actions: {
                Pill(Text("Open MimoDays", bundle: .module), isPrimary: false)
            }
            .widgetURL(WidgetLink.app)
        case let .memory(memory, canSwap):
            memoryView(memory, canSwap: canSwap)
                .widgetURL(WidgetLink.memory(memory.id))
        }
    }

    /// A picture, or for words a paper tile, when photos are on.
    private func hasTile(_ memory: WidgetPayload.Memory) -> Bool {
        showsPhotos && (image != nil || memory.kind == .text)
    }

    @ViewBuilder
    private func memoryView(_ memory: WidgetPayload.Memory, canSwap: Bool) -> some View {
        if hasTile(memory) {
            if isMedium {
                HStack(spacing: 14) {
                    PhotoTile(image: image).frame(width: 150)
                    VStack(alignment: .leading, spacing: 3) {
                        Heading(Text("Random memory", bundle: .module))
                        Group {
                            DayText(key: memory.day, style: .long).text
                            if let place = memory.place { Text(verbatim: place) }
                        }
                        .textStyle(WidgetStyle.detail)
                        .foregroundStyle(ColorToken.textBody.color)
                        .privacySensitive()
                        Spacer(minLength: 6)
                        Pill(Text("Open memory", bundle: .module), isPrimary: true)
                        if canSwap { another(AnyView(Pill(Text("Another", bundle: .module), isPrimary: false))).padding(.top, 4) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(12)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Heading(Text("Random memory", bundle: .module))
                    PhotoTile(image: image)
                        .accessibilityLabel(DayText(key: memory.day, style: .long).text)
                        .overlay(alignment: .bottomTrailing) {
                            if canSwap { another(AnyView(RoundAnother())).offset(x: 4, y: 4) }
                        }
                }
                .padding(12)
            }
        } else {
            WordsTile(heading: Text("Random memory", bundle: .module), star: false) {
                VStack(alignment: .leading, spacing: 6) {
                    Group {
                        if isMedium, let place = memory.place {
                            Text("\(DayText(key: memory.day, style: .long).string(locale)) · \(place)", bundle: .module)
                        } else {
                            DayText(key: memory.day, style: .long).text
                        }
                    }
                    .textStyle(isMedium ? WidgetStyle.titleLarge : WidgetStyle.title)
                    kindText(memory.kind)
                        .textStyle(WidgetStyle.kind)
                        .foregroundStyle(ColorToken.textBody.color)
                }
                .privacySensitive()
            } actions: {
                HStack(spacing: isMedium ? 20 : 8) {
                    Pill(Text("Open memory", bundle: .module), isPrimary: true)
                    if canSwap {
                        another(AnyView(isMedium ? AnyView(Pill(Text("Another", bundle: .module), isPrimary: false)) : AnyView(RoundAnother())))
                    }
                }
            }
        }
    }

    private func kindText(_ kind: WidgetPayload.Kind) -> Text {
        switch kind {
        case .photo: Text("A photo moment", bundle: .module)
        case .video: Text("A video moment", bundle: .module)
        case .livePhoto: Text("A Live Photo moment", bundle: .module)
        case .text: Text("A moment in words", bundle: .module)
        }
    }
}

// MARK: Pieces

private struct Heading: View {
    let text: Text
    init(_ text: Text) { self.text = text }

    var body: some View {
        text.textStyle(WidgetStyle.heading)
            .foregroundStyle(ColorToken.textPrimary.color)
            .lineLimit(1)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Heading, words, then the actions at the foot (photos off, an empty day).
private struct WordsTile<Words: View, Actions: View>: View {
    let heading: Text
    let star: Bool
    @ViewBuilder let words: Words
    @ViewBuilder let actions: Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Heading(heading)
                Spacer(minLength: 4)
                if star {
                    Icon.markStarSmall.image.resizable()
                        .frame(width: 17, height: 17.5)
                        .foregroundStyle(ColorToken.accentCoralMark.color)
                        .accessibilityHidden(true)
                }
            }
            words
                .foregroundStyle(ColorToken.textPrimary.color)
                .lineLimit(3)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
            actions
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(14)
    }
}

/// The gallery, loading, or nothing to show yet: a heading over a blank tile.
private struct PlainTile: View {
    let heading: Text

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Heading(heading)
            StripBlobA().fill(ColorToken.surfaceChip.color)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityHidden(true)
            Pill(Text("Open MimoDays", bundle: .module), isPrimary: false)
        }
        .padding(14)
        .widgetURL(WidgetLink.app)
    }
}

/// AA02/AA04 App Lock: nothing private, only MimoDays and Open MimoDays.
private struct LockedTile: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Icon.glyphLock.image.resizable()
                .frame(width: 22, height: 22)
                .foregroundStyle(ColorToken.textPrimary.color)
                .accessibilityHidden(true)
            Text(verbatim: "MimoDays").textStyle(WidgetStyle.brand)
                .foregroundStyle(ColorToken.textPrimary.color)
            Spacer(minLength: 0)
            Pill(Text("Open MimoDays", bundle: .module), isPrimary: false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(14)
        .widgetURL(WidgetLink.app)
    }
}

/// The moment's small picture in a hand-cut frame, tilted as on Mosaic; words get a paper tile with no quote.
private struct PhotoTile: View {
    let image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Color.clear.overlay { Image(uiImage: image).resizable().scaledToFill() }
            } else {
                ColorToken.surfaceCard.color
                Icon.glyphText.image.resizable()
                    .frame(width: 22, height: 22)
                    .foregroundStyle(ColorToken.accentCoralMark.color)
            }
        }
        .clipShape(StripBlobA())
        .overlay { StripBlobA().stroke(ColorToken.surfaceCard.color, lineWidth: 4) }
        .shadow(color: ColorToken.textBody.color.opacity(0.14), radius: 4, y: 3)
        .rotationEffect(.degrees(3))
        .padding(4)
        .accessibilityHidden(true)
        .privacySensitive()
    }
}

/// The year over On this day's picture.
private struct YearLabel: View {
    let key: Int

    var body: some View {
        Text(WidgetContent.date(ofDay: key, calendar: .current), format: .dateTime.year())
            .textStyle(WidgetStyle.year)
            .foregroundStyle(ColorToken.textLink.color)
            .padding(.horizontal, 6)
            .padding(.bottom, 2)
            .privacySensitive()
    }
}

private struct Pill: View {
    let text: Text
    let isPrimary: Bool
    init(_ text: Text, isPrimary: Bool) {
        self.text = text
        self.isPrimary = isPrimary
    }

    var body: some View {
        text.textStyle(WidgetStyle.pill)
            .foregroundStyle(isPrimary ? ColorToken.textOnCoral.color : ColorToken.textPrimary.color)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(ReviewChipBlob().fill(isPrimary ? ColorToken.actionCoral.color : ColorToken.surfaceChip.color))
    }
}

/// Another on a small widget: the refresh glyph on a chip.
private struct RoundAnother: View {
    var body: some View {
        Icon.glyphRefresh.image.resizable()
            .frame(width: 16, height: 16)
            .foregroundStyle(ColorToken.textPrimary.color)
            .frame(width: 30, height: 30)
            .background(ReviewChipBlob().fill(ColorToken.surfaceChip.color))
            .accessibilityLabel(Text("Another", bundle: .module))
    }
}

/// A yyyymmdd day in the widget's language: "Nov 21, 2025", or "Sat, March 8, 2025".
private struct DayText {
    enum Style { case short, long }
    let key: Int
    let style: Style

    func string(_ locale: Locale) -> String {
        let date = WidgetContent.date(ofDay: key, calendar: .current)
        return switch style {
        case .short: date.formatted(.dateTime.month(.abbreviated).day().year().locale(locale))
        case .long: date.formatted(.dateTime.weekday(.abbreviated).month(.wide).day().year().locale(locale))
        }
    }

    var text: Text {
        let date = WidgetContent.date(ofDay: key, calendar: .current)
        return switch style {
        case .short: Text(date, format: .dateTime.month(.abbreviated).day().year())
        case .long: Text(date, format: .dateTime.weekday(.abbreviated).month(.wide).day().year())
        }
    }
}
