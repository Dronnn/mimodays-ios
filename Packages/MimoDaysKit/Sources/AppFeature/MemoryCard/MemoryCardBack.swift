import Core
import DesignSystem
import Persistence
import SwiftUI

/// U30-U34: the Memory Card's back, the same size as its front. The day (heading face) over a brush stroke, the time
/// and the place, the note (or the caption when there is no note) in the hand-written face, the voice note, the collections, and a small live
/// window of the front, still playing (muted) on a video, kept at the card's bottom. Missing parts are "+" links to
/// Edit moment. It scrolls when it holds more than a short card shows.
struct MemoryCardBack: View {
    let model: MomentViewerModel
    let moment: ViewerMoment
    let playback: ViewerVideoPlayer?
    let size: CGSize
    /// The folded corner's side: bottom trailing.
    let cornerOnRight: Bool
    let edit: () -> Void
    let actions: MemoryCardActions
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    Self.day(moment.captured)
                        .textStyle(.cardBackDay)
                        .foregroundStyle(ColorToken.textPrimary.color)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .memoryCardActions(actions)
                    MemoryCardBrushUnderline()
                        .fill(Color(hex: 0xE1643A))
                        .frame(width: 196, height: 13)
                        .accessibilityHidden(true)
                }
                details
                    .padding(.top, 10)
                if moment.isHidden || moment.isHiddenWithDay {
                    HiddenFromMemoriesChip(withItsDay: moment.isHiddenWithDay)
                        .padding(.top, 10)
                        .accessibilityIdentifier("card.hiddenState")
                }
                if moment.mediaType == .text, let title = moment.title {
                    // II05: the caption over the words.
                    Text(title)
                        .textStyle(.dayCaption)
                        .foregroundStyle(ColorToken.textPrimary.color)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 26)
                }
                words
                    .padding(.top, moment.mediaType == .text && moment.title != nil ? 18 : 26)
                // CC06: the tags, then the mood, only when set.
                if !moment.tags.isEmpty || moment.mood != nil {
                    ChipFlow {
                        ForEach(moment.tags, id: \.self) { TagChip(tag: $0) }
                        if let mood = moment.mood {
                            Text("Mood: \(mood.label)", bundle: .module, comment: "Memory Card back (P8.10 CC06): the mood after it, Mood: 😄 Joyful")
                                .textStyle(.reviewChip)
                                .foregroundStyle(ColorToken.textPrimary.color)
                                .padding(.horizontal, 11)
                                .frame(minHeight: 32)
                                .background(ReviewChipBlob().fill(ColorToken.surfaceChip.color))
                        }
                    }
                    .padding(.top, 16)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("card.tagsAndMood")
                }
                // U31: "+ Record a voice note" right under "+ Write a note". A written moment is words only (II05).
                if moment.mediaType != .text {
                    voice
                        .padding(.top, moment.voice == nil && !hasWords ? 0 : 20)
                }
                if !moment.collections.isEmpty {
                    collections
                        .padding(.top, 18)
                }
                // GG05: the moments taken then and again, after the collections.
                if moment.thenNowRepeats > 0 {
                    NavigationLink(value: MemoriesRoute.thenNow(moment.id)) {
                        HStack(spacing: 6) {
                            Icon.glyphClock.image.resizable().frame(width: 16, height: 16).accessibilityHidden(true)
                            Text("Then & Now · \(moment.thenNowRepeats) repeats", bundle: .module)
                        }
                        .textStyle(.cardBackSmall)
                        .foregroundStyle(ColorToken.textPrimary.color)
                        .padding(.horizontal, 11)
                        .frame(minHeight: 32)
                        .background(ReviewChipBlob().fill(ColorToken.surfaceChip.color))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 12)
                    .accessibilityIdentifier("viewer.thenNow")
                }
                Spacer(minLength: 20)
                // No picture to show small, and no blank window (II05).
                if moment.mediaType != .text { livePreview }
            }
            .padding(.horizontal, 26)
            .padding(.top, 30)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity, minHeight: size.height, alignment: .topLeading)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .frame(width: size.width, height: size.height)
        .background(ColorToken.surfaceCard.color)
        .overlay(alignment: .bottomTrailing) {
            MemoryCardFlipCorner()
                .scaleEffect(x: cornerOnRight ? 1 : -1)
                .padding(.trailing, 7)
                .padding(.bottom, 10)
        }
        .clipShape(MemoryCardOutline())
        .overlay { MemoryCardOutline().strokeBorder(ColorToken.borderSubtle.color, lineWidth: 3).allowsHitTesting(false) }
    }

    // MARK: Pieces

    /// The time, and the place or a link to add one.
    private var details: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 22))
        return layout {
            HStack(spacing: 6) {
                Icon.glyphClock.image.resizable().frame(width: 18, height: 18).accessibilityHidden(true)
                MomentViewer.time(moment.captured, date: false)
            }
            if let place = moment.place {
                HStack(spacing: 4) {
                    Icon.glyphPin.image.resizable().frame(width: 18, height: 18).accessibilityHidden(true)
                    Text(place)
                }
            } else {
                addLink(Text("+ Add a place", bundle: .module), id: "card.addPlace")
            }
        }
        .textStyle(.viewerPlace)
        .foregroundStyle(ColorToken.textPrimary.color)
    }

    /// The note; the caption only when there is no note (Andrew, 2026-11-16: U30 has one text, and a caption alone
    /// is never lost).
    private var noteText: String? { moment.mediaType == .text ? moment.note : moment.note ?? moment.title }

    private var hasWords: Bool { noteText != nil }

    @ViewBuilder
    private var words: some View {
        if let noteText {
            Text(noteText)
                .textStyle(.dayCaption)
                .foregroundStyle(ColorToken.textPrimary.color)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text("No note yet.", bundle: .module)
                    .textStyle(.dayCaption)
                    .foregroundStyle(ColorToken.textSecondary.color)
                addLink(Text("+ Write a note", bundle: .module), id: "card.addNote")
            }
        }
    }

    @ViewBuilder
    private var voice: some View {
        if let voice = moment.voice {
            CardVoiceNote(model: model, id: moment.id, voice: voice)
        } else {
            addLink(Text("+ Record a voice note", bundle: .module), id: "card.addVoice")
        }
    }

    /// The collections it is in, each opening its collection.
    private var collections: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(moment.collections) { collection in
                NavigationLink(value: MemoriesRoute.collection(collection.id)) {
                    Text(collection.title)
                        .textStyle(.cardBackSmall)
                        .foregroundStyle(ColorToken.textSecondary.color)
                        .frame(minHeight: 24)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("viewer.collection")
            }
        }
    }

    /// The front, small, tilted and hand-cut, still playing on a video (U30).
    private var livePreview: some View {
        HStack(spacing: 14) {
            ZStack {
                if let image = model.image(moment.mainPath) {
                    Image(uiImage: image).filling()
                }
                if let playback {
                    PlayerLayerView(player: playback.main)
                }
            }
            .frame(width: 80, height: 104)
            .clipShape(CardSelfieBlob())
            .overlay { CardSelfieBlob().stroke(ColorToken.mediaFrame.color, lineWidth: 6).clipShape(CardSelfieBlob()) }
            .background {
                CardSelfieBlob()
                    .fill(ColorToken.mediaFrame.color)
                    .shadow(color: Color(hex: 0x2A1B21).opacity(0.16), radius: 9, y: 6)
            }
            .rotationEffect(.degrees(-5.4))
            .environment(\.layoutDirection, .leftToRight)
            .accessibilityHidden(true)
            if moment.mediaType == .video {
                HStack(spacing: 6) {
                    Circle().fill(ColorToken.actionCoral.color).frame(width: 8, height: 8)
                    Text("Still playing · \(Text(Duration.seconds((playback?.time ?? 0).rounded()), format: .time(pattern: .minuteSecond)))", bundle: .module)
                        .textStyle(.cardBackSmall)
                        .foregroundStyle(ColorToken.textSecondary.color)
                }
            }
        }
    }

    private func addLink(_ title: Text, id: String) -> some View {
        Button(action: edit) {
            title
                .textStyle(.cardButton)
                .foregroundStyle(ColorToken.textLink.color)
                .frame(minHeight: Size.minimumTapTarget / 2 + 8)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    /// "Wednesday, Nov 11", in the moment's own time zone.
    static func day(_ captured: CaptureTime) -> Text {
        var format = Date.FormatStyle().weekday(.wide).month(.abbreviated).day()
        format.timeZone = captured.timeZone
        return Text(captured.instant, format: format)
    }
}

/// `Card / Voice comment` (U30): play or stop, its length and its waveform on a soft capsule.
struct CardVoiceNote: View {
    let model: MomentViewerModel
    let id: UUID
    let voice: ViewerMoment.Voice

    var body: some View {
        let isPlaying = model.playingVoice == id
        let progress = isPlaying && voice.duration > 0 ? min(model.voiceTime / voice.duration, 1) : 0
        let length = Text(Duration.seconds(voice.duration.rounded()), format: .time(pattern: .minuteSecond))
        Button { model.toggleVoice(id) } label: {
            // The 9:16 back is narrower than the design's 359 pt card: fewer bars, then the length alone beside the
            // whole waveform (VoiceOver still hears "Voice note"); the label alone at the largest text sizes.
            let label = Text("Voice note · \(length)", bundle: .module)
            let filled = { (bars: Int) in Int((progress * Double(bars)).rounded()) }
            ViewThatFits(in: .horizontal) {
                row(isPlaying: isPlaying, label: label, bars: 12, filled: filled(12))
                row(isPlaying: isPlaying, label: label, bars: 8, filled: filled(8))
                row(isPlaying: isPlaying, label: length, bars: 12, filled: filled(12))
                row(isPlaying: isPlaying, label: label, bars: 0, filled: 0)
            }
            .padding(.leading, 10)
            .padding(.trailing, 16)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .background(Capsule().fill(Self.fill))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Voice note · \(length)", bundle: .module))
        .accessibilityInputLabels([Text("Voice note", bundle: .module)])
        .accessibilityValue(isPlaying ? Text(Duration.seconds(model.voiceTime.rounded()), format: .time(pattern: .minuteSecond)) : Text(verbatim: ""))
        .accessibilityHint(Text(isPlaying ? "Stops it" : "Plays it", bundle: .module))
        .accessibilityIdentifier("viewer.voice")
    }

    /// Play or stop and `label`, with a waveform of `bars` (none for 0), `filled` that far.
    private func row(isPlaying: Bool, label: Text, bars: Int, filled: Int) -> some View {
        HStack(spacing: 10) {
            (isPlaying ? Icon.glyphPause : .glyphPlay).image
                .resizable()
                .scaledToFit()
                .frame(width: 14, height: 14)
                .foregroundStyle(ColorToken.textOnCoral.color)
                .frame(width: 36, height: 36)
                .background(Circle().fill(ColorToken.actionCoral.color))
            label
                .textStyle(.viewerPlace)
                .foregroundStyle(ColorToken.textPrimary.color)
            if bars > 0 {
                Spacer(minLength: 8)
                // 3 pt bars 8 pt apart, as in the design.
                WaveformBars(
                    levels: Self.levels(model.voiceLevels[id] ?? [], bars), count: bars, filled: filled,
                    minHeight: 6, maxHeight: 16, rest: ColorToken.textSecondary.color
                )
                .frame(width: CGFloat(bars * 8), height: 18)
                .environment(\.layoutDirection, .leftToRight)
                .accessibilityHidden(true)
            }
        }
    }

    /// The waveform's levels taken down to `count` bars, each the loudest of its share (never empty: there are more
    /// levels than bars).
    static func levels(_ levels: [Float], _ count: Int) -> [Float] {
        guard count > 0, levels.count > count else { return levels }
        let total = levels.count
        return (0 ..< count).map { levels[$0 * total / count ..< ($0 + 1) * total / count].max() ?? 0 }
    }

    /// The capsule: the canvas's cream on the card's paper, a soft plum in the dark (U30, U34).
    private static let fill = Color.dynamic(light: 0xF3E8DE, dark: 0x3A3036)
}
