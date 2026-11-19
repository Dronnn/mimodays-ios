import Core
import DesignSystem
import Persistence
import SwiftUI

/// The U51-U53 sheets' top: the title on the left in the heading face, Done in coral. Every change is already saved.
private struct ItemSheetBar: View {
    let title: Text
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            title
                .textStyle(.editorTitle)
                .foregroundStyle(ColorToken.textPrimary.color)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button { dismiss() } label: {
                Text("Done", bundle: .module)
                    .textStyle(.editorDone)
                    .foregroundStyle(ColorToken.textLink.color)
                    .frame(minHeight: Size.minimumTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("sheet.done")
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
    }
}

/// A small caps-free label over a group of controls ("Cameras", "Look").
@MainActor private func groupLabel(_ text: Text) -> some View {
    text
        .textStyle(TextStyle(.body, size: 14, weight: 700, relativeTo: .subheadline))
        .foregroundStyle(ColorToken.textSecondary.color)
}

@MainActor private func footnote(_ text: Text) -> some View {
    text
        .textStyle(TextStyle(.body, size: 13, weight: 500, relativeTo: .footnote))
        .foregroundStyle(ColorToken.textSecondary.color)
        .fixedSize(horizontal: false, vertical: true)
}

@MainActor private func rowTitle(_ text: Text) -> some View {
    text.textStyle(.rowTitle).foregroundStyle(ColorToken.textPrimary.color)
}

// MARK: - U52 Clip: cameras and sound

/// U52: which camera goes where in this clip, its own sound and level, and its voice comment. The window itself is
/// dragged and pinched on the stage above while this is open.
struct ClipSheet: View {
    let model: MovieEditorModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ItemSheetBar(title: Text("Clip \(model.selectedClipNumber)", bundle: .module))
                if model.selectedPlan?.selfieURL != nil {
                    groupLabel(Text("Cameras", bundle: .module))
                        .padding(.horizontal, 20)
                        .padding(.top, 14)
                    layouts
                        .padding(.top, 8)
                    footnote(Text("Drag the window in the preview to place it; pinch to resize. The movie uses exactly this.", bundle: .module))
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                }
                sound
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
            }
            .padding(.bottom, 20)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(ColorToken.surfaceSheet.color.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        .presentationDragIndicator(.visible)
    }

    /// U52: five tiles across the sheet; at large text sizes they scroll.
    private var layouts: some View {
        ViewThatFits(in: .horizontal) {
            layoutRow(fills: true)
                .padding(.horizontal, 20)
            ScrollView(.horizontal) {
                layoutRow(fills: false)
                    .padding(.horizontal, 20)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func layoutRow(fills: Bool) -> some View {
        let current = model.selectedPlan?.layout ?? .window
        return HStack(spacing: 6) {
            ForEach(ClipCameraLayout.allCases, id: \.self) { layout in
                let isOn = layout == current
                Button { model.setCameraLayout(layout) } label: {
                    VStack(spacing: 6) {
                        LayoutGlyph(layout: layout)
                            .frame(width: 30, height: 40)
                        layout.title
                            .textStyle(TextStyle(.body, size: 11, weight: 800, relativeTo: .caption2, maximumScale: 1.35))
                            .foregroundStyle(ColorToken.textPrimary.color)
                            .lineLimit(1)
                            .fixedSize()
                    }
                    .padding(.horizontal, 4)
                    .frame(minWidth: 62, maxWidth: fills ? .infinity : nil, minHeight: 80)
                    .background {
                        ReviewChipBlob().fill((isOn ? ColorToken.accentPeach : .surfaceChip).color)
                        if isOn { ReviewChipBlob().stroke(ColorToken.actionCoral.color, lineWidth: 2) }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? .isSelected : [])
                .accessibilityIdentifier("clip.layout.\(layout.rawValue)")
            }
        }
    }

    @ViewBuilder
    private var sound: some View {
        let clip = model.selectedClip
        if case let .video(_, _, hasAudio) = model.selectedPlan?.media, hasAudio {
            Toggle(isOn: Binding(get: { clip?.clipAudio != .muted }, set: model.setClipSound)) { rowTitle(Text("Original sound", bundle: .module)) }
                .tint(ColorToken.actionCoral.color)
                .accessibilityIdentifier("clip.sound")
            if clip?.clipAudio != .muted {
                HStack {
                    rowTitle(Text("Volume", bundle: .module))
                    Spacer()
                    Text(clip?.clipVolume ?? 1, format: .percent.precision(.fractionLength(0)))
                        .textStyle(TextStyle(.body, size: 14, weight: 600, relativeTo: .footnote))
                        .foregroundStyle(ColorToken.textSecondary.color)
                }
                .padding(.top, 10)
                LevelSlider(value: Binding(get: { clip?.clipVolume ?? 1 }, set: model.setClipVolume)) { changing in
                    if changing { model.beginLevelChange() } else { model.endLevelChange() }
                }
                .padding(.top, 8)
                .accessibilityLabel(Text("Volume", bundle: .module))
                .accessibilityIdentifier("clip.volume")
            }
        }
        if let note = model.selectedVoiceNote {
            Toggle(isOn: Binding(get: { clip?.includesVoiceNote ?? false }, set: model.setIncludesVoiceNote)) {
                rowTitle(Text("Voice comment", bundle: .module))
            }
            .tint(ColorToken.actionCoral.color)
            .padding(.top, 14)
            .accessibilityIdentifier("clip.voice")
            footnote(Text("Plays over this clip · \(MovieEditorView.clock(note.duration)) · clip sound dips while it plays", bundle: .module))
                .padding(.top, 4)
        }
    }
}

/// `Editor / Window`, `Swapped`, `Main`, `Selfie`, `Side by side`: the two cameras in coral (main) and blue (selfie).
private struct LayoutGlyph: View {
    let layout: ClipCameraLayout
    private let main = Color(hex: 0xC97456)
    private let selfie = Color(hex: 0x7FA3B5)

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let window = CGSize(width: size.width * 0.38, height: size.height * 0.36)
            switch layout {
            case .window, .swapped:
                let (back, front) = layout == .window ? (main, selfie) : (selfie, main)
                RoundedRectangle(cornerRadius: 4, style: .continuous).fill(back)
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(front)
                    .overlay(RoundedRectangle(cornerRadius: 2, style: .continuous).strokeBorder(.white, lineWidth: 1.2))
                    .frame(width: window.width, height: window.height)
                    .rotationEffect(.degrees(-5.4))
                    .position(x: size.width - window.width / 2 - 2, y: window.height / 2 + 3)
            case .mainOnly:
                RoundedRectangle(cornerRadius: 4, style: .continuous).fill(main)
            case .selfieOnly:
                RoundedRectangle(cornerRadius: 4, style: .continuous).fill(selfie)
            case .sideBySide:
                VStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous).fill(main)
                    RoundedRectangle(cornerRadius: 4, style: .continuous).fill(selfie)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

extension ClipCameraLayout {
    var title: Text {
        switch self {
        case .window: Text("Window", bundle: .module, comment: "U52: the selfie in its window over the main camera")
        case .swapped: Text("Swapped", bundle: .module, comment: "U52: the main camera in the window over the selfie")
        case .mainOnly: Text("Main", bundle: .module, comment: "U52: only the main camera")
        case .selfieOnly: Text("Selfie", bundle: .module, comment: "U52: only the selfie camera")
        case .sideBySide: Text("Side by side", bundle: .module, comment: "U52: both cameras, each filling half")
        }
    }
}

// MARK: - U51 Text card

/// U51: the card's words, its look, how long it shows, and a voice comment over it.
struct CardSheet: View {
    let model: MovieEditorModel
    @State private var text = ""
    /// The card this sheet opened on: playback moving the selection on doesn't send its text to another card.
    @State private var card: MovieTextCard?
    @FocusState private var isEditing: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ItemSheetBar(title: Text("Text card", bundle: .module))
                if let card = model.selectedCard {
                    HStack(alignment: .top, spacing: 16) {
                        preview(card)
                        VStack(alignment: .leading, spacing: 0) {
                            field
                            groupLabel(Text("Look", bundle: .module))
                                .padding(.top, 14)
                            SegmentedControl(selection: Binding(get: { card.look }, set: model.setCardLook), options: TextCardLook.allCases, labelSize: 14) {
                                $0.title
                            }
                            .padding(.top, 6)
                            .accessibilityIdentifier("card.look")
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
                    HStack {
                        rowTitle(Text("On screen", bundle: .module))
                        Spacer(minLength: 12)
                        SegmentedControl(selection: Binding(get: { card.duration }, set: model.setCardDuration), options: MovieEditorModel.cardDurations, labelSize: 14) {
                            Text("\(Int($0)) s", bundle: .module, comment: "U51: how many seconds the card shows")
                        }
                        .frame(width: 232)
                        .accessibilityIdentifier("card.duration")
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    voice
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                    footnote(Text("Shown before the first clip. Drag it on the timeline to move it between clips.", bundle: .module))
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                }
            }
            .padding(.bottom, 20)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(ColorToken.surfaceSheet.color.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        .presentationDragIndicator(.visible)
        .onAppear {
            card = model.selectedCard
            text = card?.text ?? ""
        }
        .onChange(of: isEditing) { _, editing in if !editing, let card { model.setCardText(text, of: card) } }
        // Another card picked on the timeline behind the sheet (iPad, medium): the words follow it too, the first
        // card's kept. Playback moving on to a clip leaves the card as it is.
        .onChange(of: model.selectedCard?.id) {
            guard let next = model.selectedCard, next.id != card?.id else { return }
            if let card { model.setCardText(text, of: card) }
            card = next
            text = next.text
        }
        .onDisappear { if let card { model.setCardText(text, of: card) } }
    }

    /// The card as it shows, in small.
    private func preview(_ card: MovieTextCard) -> some View {
        let dark = card.look != .paper
        return Text(text.isEmpty ? card.text : text)
            .textStyle(TextStyle(.heading, size: 17, weight: 700, relativeTo: .headline, maximumScale: 1))
            .foregroundStyle(dark ? ColorToken.mediaFrame.color : ColorToken.textPrimary.color)
            .multilineTextAlignment(.center)
            .padding(8)
            .frame(width: 100, height: 150)
            .background(DayCardBlob().fill(dark ? Color(hex: 0x4B2938) : ColorToken.surfaceCard.color))
            .overlay(DayCardBlob().stroke(ColorToken.borderSubtle.color, lineWidth: 1))
            .accessibilityHidden(true)
    }

    private var field: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField(text: $text, axis: .vertical) { Text("A few words", bundle: .module) }
                .textStyle(.rowTitle)
                .foregroundStyle(ColorToken.textPrimary.color)
                .lineLimit(1...3)
                .focused($isEditing)
                .submitLabel(.done)
                .onChange(of: text) { _, new in if new.count > MovieEditorModel.cardLimit { text = String(new.prefix(MovieEditorModel.cardLimit)) } }
                .accessibilityIdentifier("card.text")
            Text("Up to \(MovieEditorModel.cardLimit) characters", bundle: .module)
                .textStyle(TextStyle(.body, size: 12, weight: 500, relativeTo: .caption1))
                .foregroundStyle(ColorToken.textSecondary.color)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FieldBlob().fill(ColorToken.surfaceChip.color))
    }

    @ViewBuilder
    private var voice: some View {
        let notes = model.voiceNotes
        if !notes.isEmpty {
            Toggle(isOn: Binding(get: { model.selectedCardVoice != nil }, set: model.setCardHasVoice)) {
                rowTitle(Text("Voice over this card", bundle: .module))
            }
            .tint(ColorToken.actionCoral.color)
            .accessibilityIdentifier("card.voice")
            if let note = model.selectedCardVoice {
                HStack(spacing: 8) {
                    Icon.glyphMic.image.resizable().frame(width: 20, height: 20).accessibilityHidden(true)
                    Text("Voice comment from \(note.recordedAt.formatted(.dateTime.month(.abbreviated).day().locale(AppLanguage.shared.locale))) · \(MovieEditorView.clock(note.duration))", bundle: .module)
                        .textStyle(TextStyle(.body, size: 14, weight: 700, relativeTo: .subheadline))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Menu {
                        ForEach(notes, id: \.id) { other in
                            Button {
                                model.setCardVoice(other)
                            } label: {
                                Text(verbatim: "\(other.recordedAt.formatted(.dateTime.month(.abbreviated).day().locale(AppLanguage.shared.locale))) · \(MovieEditorView.clock(other.duration))")
                            }
                        }
                    } label: {
                        Text("Change", bundle: .module)
                            .textStyle(TextStyle(.body, size: 14, weight: 800, relativeTo: .subheadline))
                            .foregroundStyle(ColorToken.textLink.color)
                            .frame(minHeight: Size.minimumTapTarget)
                    }
                    .accessibilityIdentifier("card.voice.change")
                }
                .foregroundStyle(ColorToken.textPrimary.color)
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .background(Capsule().fill(ColorToken.accentPeach.color))
                .padding(.top, 8)
            }
        }
    }
}

extension TextCardLook {
    var title: Text {
        switch self {
        case .paper: Text("Paper", bundle: .module, comment: "U51: a text card on cream paper")
        case .plum: Text("Plum", bundle: .module, comment: "U51: a text card on dark plum")
        case .overClip: Text("Over clip", bundle: .module, comment: "U51: a text card over the next clip's first frame")
        }
    }
}

// MARK: - U53 Transition

/// U53: how the item at `index` comes in. Atmosphere lets its sound lead and the picture fade in after.
struct TransitionSheet: View {
    let model: MovieEditorModel
    let index: Int

    var body: some View {
        let transition = model.transition(at: index)
        let atmosphere = model.atmosphere(at: index)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ItemSheetBar(title: title)
                SegmentedControl(selection: Binding(get: { transition }, set: { model.setTransition($0, at: index) }), options: MovieTransition.allCases, labelSize: 15) {
                    $0.title
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .accessibilityIdentifier("transition.kind")
                footnote(explanation(transition))
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                if transition == .atmosphere {
                    AtmosphereDiagram(lead: atmosphere.lead)
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                    HStack {
                        rowTitle(Text("Sound leads by", bundle: .module))
                        Spacer()
                        Text(Self.seconds(atmosphere.lead))
                            .textStyle(TextStyle(.body, size: 14, weight: 600, relativeTo: .footnote))
                            .foregroundStyle(ColorToken.textSecondary.color)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    LeadSlider(lead: atmosphere.lead) { lead in
                        model.setAtmosphere(MovieAtmosphere(lead: lead, leadsWith: atmosphere.leadsWith), at: index)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    rowTitle(Text("Lead with", bundle: .module))
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                    SegmentedControl(
                        selection: Binding(get: { atmosphere.leadsWith }, set: { model.setAtmosphere(MovieAtmosphere(lead: atmosphere.lead, leadsWith: $0), at: index) }),
                        options: MovieAtmosphere.Lead.allCases, labelSize: 15
                    ) { lead in
                        switch lead {
                        case .clipSound: Text("Clip sound", bundle: .module)
                        case .voiceComment: Text("Voice comment", bundle: .module)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .accessibilityIdentifier("transition.leadsWith")
                    footnote(Text("The fade-in time follows the lead (\(Self.seconds(atmosphere.lead * MovieComposer.atmosphereFade))).", bundle: .module))
                        .padding(.horizontal, 20)
                        .padding(.top, 10)
                }
            }
            .padding(.bottom, 20)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(ColorToken.surfaceSheet.color.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    /// "Between clip 1 and 2", or which item it leads into.
    private var title: Text {
        Text("Between \(model.itemName(index - 1)) and \(model.itemName(index))", bundle: .module, comment: "U53: the transition sheet's title, e.g. Between clip 1 and clip 2")
    }

    private func explanation(_ transition: MovieTransition) -> Text {
        switch transition {
        case .cut: Text("The next one starts straight away.", bundle: .module)
        case .fade: Text("The picture dips through black.", bundle: .module)
        case .atmosphere: Text("Sound comes first, then the picture fades in.", bundle: .module)
        }
    }

    static func seconds(_ value: Double) -> String {
        String(appLocalized: "\(value.formatted(.number.precision(.fractionLength(1)).locale(AppLanguage.shared.locale))) s", bundle: .module, comment: "U53: seconds, e.g. 2.0 s")
    }
}

/// U53's little picture of it: the picture dark, then rising; the sound running all along, the lead marked.
private struct AtmosphereDiagram: View {
    let lead: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                label(Text("Picture", bundle: .module))
                GeometryReader { proxy in
                    let leadWidth = proxy.size.width * CGFloat(lead / (MovieAtmosphere.leadRange.upperBound + 2))
                    let fade = leadWidth * MovieComposer.atmosphereFade
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color(hex: 0x2A1B21)).frame(width: max(leadWidth, 6), height: 16)
                        Path { path in
                            path.move(to: CGPoint(x: leadWidth, y: 16))
                            path.addLine(to: CGPoint(x: leadWidth + fade, y: 0))
                            path.addLine(to: CGPoint(x: leadWidth + fade, y: 16))
                            path.closeSubpath()
                        }
                        .fill(Color(hex: 0x7FA3B5))
                        Capsule().fill(Color(hex: 0x7FA3B5)).frame(height: 16).padding(.leading, leadWidth + fade)
                    }
                    .frame(height: 16)
                }
                .frame(height: 16)
            }
            HStack(spacing: 12) {
                label(Text("Sound", bundle: .module))
                GeometryReader { proxy in
                    let leadWidth = proxy.size.width * CGFloat(lead / (MovieAtmosphere.leadRange.upperBound + 2))
                    ZStack(alignment: .topLeading) {
                        Path { path in
                            path.move(to: CGPoint(x: 0, y: 6))
                            path.addLine(to: CGPoint(x: proxy.size.width, y: 6))
                        }
                        .stroke(ColorToken.actionCoral.color, style: StrokeStyle(lineWidth: 2, dash: [2, 4]))
                        Rectangle().fill(ColorToken.textSecondary.color).frame(width: 1, height: 12).offset(x: leadWidth)
                        Text(verbatim: TransitionSheet.seconds(lead))
                            .textStyle(TextStyle(.body, size: 11, weight: 800, relativeTo: .caption2, maximumScale: 1))
                            .foregroundStyle(ColorToken.actionCoral.color)
                            .offset(y: 14)
                    }
                }
                .frame(height: 30)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(ColorToken.surfaceChip.color))
        .accessibilityElement()
        .accessibilityLabel(Text("Sound leads by \(TransitionSheet.seconds(lead)), then the picture fades in", bundle: .module))
    }

    private func label(_ text: Text) -> some View {
        text
            .textStyle(TextStyle(.body, size: 11, weight: 800, relativeTo: .caption2, maximumScale: 1))
            .textCase(.uppercase)
            .foregroundStyle(ColorToken.textSecondary.color)
            .frame(width: 60, alignment: .leading)
    }
}

/// The lead in tenths of a second over `MovieAtmosphere.leadRange`; one Undo step per drag.
private struct LeadSlider: View {
    let lead: Double
    let set: (Double) -> Void
    @State private var value: Double?

    var body: some View {
        let range = MovieAtmosphere.leadRange
        LevelSlider(
            value: Binding(
                get: { ((value ?? lead) - range.lowerBound) / (range.upperBound - range.lowerBound) },
                set: { value = ((range.lowerBound + $0 * (range.upperBound - range.lowerBound)) * 10).rounded() / 10 }
            ),
            changing: { changing in
                if !changing, let value {
                    set(value)
                    self.value = nil
                }
            }
        )
        .accessibilityLabel(Text("Sound leads by", bundle: .module))
        .accessibilityValue(Text(verbatim: TransitionSheet.seconds(value ?? lead)))
        .accessibilityIdentifier("transition.lead")
    }
}
