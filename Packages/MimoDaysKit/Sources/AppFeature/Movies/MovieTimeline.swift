import DesignSystem
import Persistence
import SwiftUI

/// U50 `Editor / Lanes`: the picture lane (clips and text cards in play order, a dot between two items for their
/// transition), each clip's own sound, the voice comments and the music, scrolled together under one playhead.
/// Items are as wide as they play long. Tap to choose, long-press and drag to move, tap a dot to change it.
struct MovieTimeline: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.locale) private var locale
    let model: MovieEditorModel
    /// A transition dot: the item it leads into.
    let transition: (Int) -> Void

    /// Points per second of movie, and the narrowest an item gets.
    static let pointsPerSecond: CGFloat = 12
    static let narrowest: CGFloat = 52
    static let spacing: CGFloat = 4
    static let laneHeight: CGFloat = 48
    static let gutter: CGFloat = 44

    var body: some View {
        let widths = model.plan.clips.map { Self.width($0.duration) }
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                laneIcon(.glyphPhotos, Text("Picture", bundle: .module))
                laneIcon(.glyphSpeaker, Text("Original sound", bundle: .module))
                laneIcon(.glyphMic, Text("Voice comments", bundle: .module))
                laneIcon(.glyphMusic, model.track?.kind == .voiceover ? Text("Your voice", bundle: .module) : Text("Music", bundle: .module))
            }
            .frame(width: Self.gutter)
            ScrollViewReader { reader in
                ScrollView(.horizontal) {
                    VStack(alignment: .leading, spacing: 0) {
                        pictureLane(widths)
                        soundLane(widths)
                        voiceLane(widths)
                        musicLane(widths)
                    }
                    .overlay(alignment: .topLeading) { playhead(widths) }
                    .padding(.trailing, 16)
                }
                .scrollIndicators(.hidden)
                .onChange(of: model.selected) { _, index in
                    withAnimation(reduceMotion ? nil : .snappy) { reader.scrollTo(index, anchor: .center) }
                }
            }
        }
        .frame(height: Self.laneHeight * 4)
        // Time runs left to right in every language, as on the preview's scrubber: the playhead's offset, the lanes
        // and a touch agree (rev-library).
        .environment(\.layoutDirection, .leftToRight)
    }

    static func width(_ duration: Double) -> CGFloat {
        max(CGFloat(duration) * pointsPerSecond, narrowest)
    }

    private func laneIcon(_ icon: Icon, _ label: Text) -> some View {
        icon.image
            .resizable()
            .frame(width: 22, height: 22)
            .foregroundStyle(ColorToken.textPrimary.color)
            .frame(width: Self.gutter, height: Self.laneHeight)
            .overlay(alignment: .bottom) { separator }
            .accessibilityElement()
            .accessibilityLabel(label)
    }

    private var separator: some View {
        Color(hex: 0x4B2938).opacity(0.1).frame(height: 1)
    }

    private func lane(@ViewBuilder _ content: () -> some View) -> some View {
        HStack(spacing: Self.spacing) { content() }
            .frame(height: Self.laneHeight)
            .overlay(alignment: .bottom) { separator.padding(.leading, -Self.gutter) }
    }

    // MARK: Picture

    private func pictureLane(_ widths: [CGFloat]) -> some View {
        lane {
            ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                tile(item, index: index, width: widths.indices.contains(index) ? widths[index] : Self.narrowest)
                    .id(index)
                    .overlay(alignment: .leading) {
                        if index > 0 { dot(index).offset(x: -Self.spacing / 2 - 10) }
                    }
                    .zIndex(index == model.selected ? 1 : 0)
            }
        }
    }

    private func tile(_ item: MovieEditorModel.Item, index: Int, width: CGFloat) -> some View {
        let isSelected = index == model.selected
        let shape = Self.blob(index)
        return Group {
            switch item {
            case let .clip(clip): clipFace(clip)
            case let .card(card): cardFace(card)
            }
        }
        .frame(width: width, height: 40)
        .clipShape(shape)
        .overlay { if isSelected { shape.stroke(ColorToken.actionCoral.color, lineWidth: 3) } }
        .contentShape(Rectangle())
        .onTapGesture { model.select(index) }
        .draggable(String(index)) {
            Group {
                switch item {
                case let .clip(clip): clipFace(clip)
                case let .card(card): cardFace(card)
                }
            }
            .frame(width: width, height: 40)
            .clipShape(shape)
        }
        .dropDestination(for: String.self) { items, _ in
            guard let source = items.first.flatMap(Int.init) else { return false }
            model.move(from: source, to: index)
            return true
        }
        .accessibilityElement()
        .accessibilityLabel(label(item, index: index))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { model.select(index) }
        .accessibilityAction(named: Text("Move earlier", bundle: .module)) { model.move(from: index, to: index - 1) }
        .accessibilityAction(named: Text("Move later", bundle: .module)) { model.move(from: index, to: index + 1) }
        .accessibilityIdentifier(item.card == nil ? "editor.clip" : "editor.card")
    }

    private static func blob(_ index: Int) -> AnyShape {
        switch index % 3 {
        case 0: AnyShape(StripBlobA())
        case 1: AnyShape(StripBlobB())
        default: AnyShape(StripBlobC())
        }
    }

    /// rev-library: the picture is read when the clip scrolls into view, and again if the cache let it go meanwhile;
    /// clips far along a long timeline don't all load at once.
    private func clipFace(_ clip: MovieClip) -> some View {
        let id = clip.moment?.id
        return Color(hex: 0xC9B8AA)
            .overlay {
                if let id, let image = model.tiles.images[id] { Image(uiImage: image).filling() }
            }
            .onScrollVisibilityChange(threshold: 0.01) { visible in
                guard visible, let id else { return }
                Task { await model.tiles.load(id) }
            }
    }

    /// `Editor / Text card` on the lane: "Aa" in coral and the words, on paper or plum.
    private func cardFace(_ card: MovieTextCard) -> some View {
        let dark = card.look != .paper
        return VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: "Aa")
                .textStyle(TextStyle(.body, size: 11, weight: 800, relativeTo: .caption2, maximumScale: 1))
                .foregroundStyle(ColorToken.actionCoral.color)
            Text(card.text)
                .textStyle(TextStyle(.body, size: 12, weight: 700, relativeTo: .caption2, maximumScale: 1))
                .foregroundStyle(dark ? ColorToken.mediaFrame.color : ColorToken.textPrimary.color)
                .lineLimit(1)
        }
        .padding(.horizontal, 7)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(dark ? Color(hex: 0x4B2938) : ColorToken.surfaceCard.color)
    }

    /// The transition into item `index`: a coral wave for Atmosphere, a slash for a fade, a small dot for a cut.
    private func dot(_ index: Int) -> some View {
        let transition = model.transition(at: index)
        return Button { self.transition(index) } label: {
            ZStack {
                switch transition {
                case .cut:
                    Circle().fill(ColorToken.surfaceChip.color).overlay(Circle().strokeBorder(ColorToken.textSecondary.color, lineWidth: 1)).frame(width: 10, height: 10)
                case .fade:
                    Circle().fill(ColorToken.textSecondary.color).frame(width: 20, height: 20)
                        .overlay { Text(verbatim: "⁄").font(.system(size: 13, weight: .bold)).foregroundStyle(ColorToken.mediaFrame.color) }
                case .atmosphere:
                    Circle().fill(ColorToken.actionCoral.color).frame(width: 20, height: 20)
                        .overlay { Image(systemName: "water.waves").font(.system(size: 9, weight: .bold)).foregroundStyle(ColorToken.mediaFrame.color) }
                }
            }
            .frame(width: 20, height: Size.minimumTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Transition into item \(index + 1)", bundle: .module))
        .accessibilityValue(transition.title)
        .accessibilityIdentifier("editor.transition.\(index)")
    }

    // MARK: Sound

    /// Each video's own sound as bars, its level when it isn't full, a dashed outline when it's off.
    private func soundLane(_ widths: [CGFloat]) -> some View {
        lane {
            ForEach(Array(model.plan.clips.enumerated()), id: \.offset) { index, clip in
                let width = widths[index]
                Group {
                    if case let .video(_, _, hasAudio) = clip.media, hasAudio {
                        if clip.soundOn {
                            WaveBars(seed: clip.momentID.hashValue, color: ColorToken.textSecondary.color)
                                .overlay(alignment: .top) {
                                    if clip.volume < 0.995 {
                                        Text(clip.volume, format: .percent.precision(.fractionLength(0)))
                                            .textStyle(TextStyle(.body, size: 10, weight: 800, relativeTo: .caption2, maximumScale: 1))
                                            .foregroundStyle(ColorToken.textPrimary.color)
                                            .offset(y: -2)
                                    }
                                }
                        } else {
                            ReviewChipBlob()
                                .stroke(ColorToken.textSecondary.color, style: StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
                                .overlay {
                                    Text("muted", bundle: .module, comment: "U50: a clip whose own sound is off")
                                        .textStyle(TextStyle(.body, size: 10, weight: 700, relativeTo: .caption2, maximumScale: 1))
                                        .foregroundStyle(ColorToken.textSecondary.color)
                                }
                                .padding(.vertical, 8)
                        }
                    } else {
                        Color.clear
                    }
                }
                .frame(width: width, height: 34)
                .accessibilityHidden(true)
            }
        }
    }

    // MARK: Voice

    /// Where voice comments play: coral shapes with bars, as long as they last within their item.
    private func voiceLane(_ widths: [CGFloat]) -> some View {
        lane {
            ForEach(Array(model.plan.clips.enumerated()), id: \.offset) { index, clip in
                let width = widths[index]
                let length = model.voiceLength(at: index).map { min(Self.width($0), width) }
                ZStack(alignment: .leading) {
                    Color.clear
                    if let length {
                        FieldBlob()
                            .fill(ColorToken.actionCoral.color)
                            .overlay { WaveBars(seed: index &* 31, color: ColorToken.mediaFrame.color).padding(.horizontal, 6) }
                            .frame(width: length, height: 30)
                    }
                }
                .frame(width: width)
                .accessibilityHidden(true)
            }
        }
    }

    // MARK: Music

    /// The song or the voice under the whole movie: its name and level on a sage band, with a song's fade in and out
    /// drawn.
    private func musicLane(_ widths: [CGFloat]) -> some View {
        let total = widths.reduce(0, +) + Self.spacing * CGFloat(max(widths.count - 1, 0))
        return lane {
            if let music = model.track {
                RibbonBlob()
                    .fill(ColorToken.accentSage.color.opacity(0.55))
                    // The voice doesn't fade.
                    .overlay { if music.kind == .soundtrack { MusicEnvelope().stroke(Color(hex: 0x4F6B4A), lineWidth: 1.5) } }
                    .overlay(alignment: .leading) {
                        Text(verbatim: "\(music.title) · \(music.gain.formatted(.percent.precision(.fractionLength(0)).locale(locale)))")
                            .textStyle(TextStyle(.body, size: 11, weight: 700, relativeTo: .caption2, maximumScale: 1))
                            .foregroundStyle(Color(hex: 0x3B4E37))
                            .lineLimit(1)
                            .padding(.leading, 40)
                    }
                    .frame(width: total, height: 34)
                    .accessibilityHidden(true)
            } else {
                Color.clear.frame(width: total)
            }
        }
    }

    // MARK: Playhead

    /// The coral line and knob at the movie's time, across every lane.
    private func playhead(_ widths: [CGFloat]) -> some View {
        let starts = model.starts
        var x: CGFloat = 0
        if let playhead = model.playhead, widths.indices.contains(playhead.index) {
            x = widths.prefix(playhead.index).reduce(0, +) + Self.spacing * CGFloat(playhead.index) + widths[playhead.index] * playhead.fraction
        } else if starts.isEmpty {
            x = 0
        }
        return ZStack(alignment: .top) {
            Capsule().fill(ColorToken.actionCoral.color).frame(width: 2, height: Self.laneHeight * 4)
            Circle().fill(ColorToken.actionCoral.color).frame(width: 11, height: 11).offset(y: -5)
        }
        .offset(x: x - 1)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func label(_ item: MovieEditorModel.Item, index: Int) -> Text {
        switch item {
        case .clip:
            let number = model.items.prefix(index + 1).count { $0.clip != nil }
            return Text("Clip \(number) of \(model.clipCount)", bundle: .module)
        case let .card(card):
            return Text("Text card: \(card.text)", bundle: .module)
        }
    }
}

/// Bars that read as sound, the same for the same seed.
private struct WaveBars: View {
    let seed: Int
    let color: Color

    var body: some View {
        Canvas { context, size in
            var generator = SplitMix(seed: UInt64(bitPattern: Int64(seed)))
            let step: CGFloat = 4
            var x: CGFloat = 1
            while x < size.width - 1 {
                let height = size.height * (0.25 + 0.7 * CGFloat(generator.next() % 1000) / 1000)
                let bar = CGRect(x: x, y: (size.height - height) / 2, width: 2, height: height)
                context.fill(Path(roundedRect: bar, cornerRadius: 1), with: .color(color))
                x += step
            }
        }
    }
}

/// The music's level line: up over the first stretch, along, and down at the end.
private struct MusicEnvelope: Shape {
    func path(in rect: CGRect) -> Path {
        let fade = min(rect.width * 0.12, 40)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + 4, y: rect.maxY - 4))
        path.addLine(to: CGPoint(x: rect.minX + fade, y: rect.minY + 6))
        path.addLine(to: CGPoint(x: rect.maxX - fade, y: rect.minY + 6))
        path.addLine(to: CGPoint(x: rect.maxX - 4, y: rect.maxY - 4))
        return path
    }
}

private struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

extension MovieTransition {
    var title: Text {
        switch self {
        case .cut: Text("Cut", bundle: .module)
        case .fade: Text("Fade", bundle: .module)
        case .atmosphere: Text("Atmosphere", bundle: .module)
        }
    }
}
