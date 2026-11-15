import Core
import DesignSystem
import Persistence
import SwiftUI

/// U30-U34: the Memory Card's back, the same size as its front. The day (Fraunces) over a brush stroke, the time
/// and the place, the caption and note in the hand-written face, the voice note, the collections, and a small live
/// window of the front, still playing (muted) on a video. Missing parts are "+" links to Edit moment. It scrolls
/// when it holds more than a short card shows.
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
                words
                    .padding(.top, 26)
                voice
                    .padding(.top, 20)
                if !moment.collections.isEmpty {
                    collections
                        .padding(.top, 18)
                }
                livePreview
                    .padding(.top, 20)
            }
            .padding(.horizontal, 26)
            .padding(.top, 30)
            .padding(.bottom, 56)
            .frame(maxWidth: .infinity, alignment: .leading)
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

    @ViewBuilder
    private var words: some View {
        if moment.title != nil || moment.note != nil {
            MomentWords(moment: moment, onPhoto: false)
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

    /// The front, small and tilted, still playing on a video (U30).
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
            .frame(width: 72, height: 96)
            .clipShape(MemoryCardOutline())
            .overlay { MemoryCardOutline().strokeBorder(ColorToken.mediaFrame.color, lineWidth: 3) }
            .background {
                MemoryCardOutline()
                    .fill(ColorToken.mediaFrame.color)
                    .shadow(color: ColorToken.textPrimary.color.opacity(0.16), radius: 9, y: 6)
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
            // A card narrower than the design's 359 pt leaves the waveform out rather than squeeze the label.
            ViewThatFits(in: .horizontal) {
                row(isPlaying: isPlaying, length: length, waveform: Int((progress * 12).rounded()))
                row(isPlaying: isPlaying, length: length, waveform: nil)
            }
            .padding(.leading, 10)
            .padding(.trailing, 16)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .background(Capsule().fill(Self.fill))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Voice note · \(length)", bundle: .module))
        .accessibilityValue(isPlaying ? Text(Duration.seconds(model.voiceTime.rounded()), format: .time(pattern: .minuteSecond)) : Text(verbatim: ""))
        .accessibilityHint(Text(isPlaying ? "Stops it" : "Plays it", bundle: .module))
        .accessibilityIdentifier("viewer.voice")
    }

    /// Play or stop and the length, with the waveform `filled` that far when it is shown.
    private func row(isPlaying: Bool, length: Text, waveform filled: Int?) -> some View {
        HStack(spacing: 10) {
            (isPlaying ? Icon.glyphPause : .glyphPlay).image
                .resizable()
                .scaledToFit()
                .frame(width: 14, height: 14)
                .foregroundStyle(ColorToken.textOnCoral.color)
                .frame(width: 36, height: 36)
                .background(Circle().fill(ColorToken.actionCoral.color))
            Text("Voice note · \(length)", bundle: .module)
                .textStyle(.viewerPlace)
                .foregroundStyle(ColorToken.textPrimary.color)
            if let filled {
                Spacer(minLength: 8)
                WaveformBars(
                    levels: model.voiceLevels[id] ?? [], count: 12, filled: filled,
                    minHeight: 6, maxHeight: 16, rest: ColorToken.textSecondary.color
                )
                .frame(width: 92, height: 18)
                .environment(\.layoutDirection, .leftToRight)
                .accessibilityHidden(true)
            }
        }
    }

    /// The capsule: the canvas's cream on the card's paper, a soft plum in the dark (U30, U34).
    private static let fill = Color.dynamic(light: 0xF3E8DE, dark: 0x3A3036)
}
