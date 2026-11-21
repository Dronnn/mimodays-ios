import Core
import DesignSystem
import Persistence
import SwiftUI

// MARK: Mood (P8.10)

extension Mood {
    /// Its name, as the picker, the chips and the card say it.
    var name: Text {
        switch self {
        case .joyful: Text("Joyful", bundle: .module, comment: "Mood (P8.10): the happiest of five")
        case .calm: Text("Calm", bundle: .module, comment: "Mood (P8.10)")
        case .okay: Text("Okay", bundle: .module, comment: "Mood (P8.10): neither good nor bad")
        case .low: Text("Low", bundle: .module, comment: "Mood (P8.10): a bit down")
        case .heavy: Text("Heavy", bundle: .module, comment: "Mood (P8.10): the saddest of five")
        }
    }

    /// "😄 Joyful".
    var label: Text { Text(verbatim: emoji + " ") + name }
}

/// Tags as one line: "#bike, #lena".
enum TagList {
    static func text(_ tags: [String]) -> String {
        tags.map { "#" + $0 }.formatted(.list(type: .and, width: .narrow).locale(AppLanguage.shared.locale))
    }
}

// MARK: Chips

/// Chips in rows, wrapping to the next row when one doesn't fit (CC01, CC03, CC06).
struct ChipFlow: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let places = rows(subviews, width: proposal.width ?? .infinity).flatMap(\.self)
        let width = places.map { $0.x + $0.size.width }.max() ?? 0
        let height = places.map { $0.y + $0.size.height }.max() ?? 0
        return CGSize(width: proposal.width.map { min($0, width) } ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        for (index, place) in rows(subviews, width: bounds.width).flatMap(\.self).enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + place.x, y: bounds.minY + place.y), proposal: ProposedViewSize(place.size))
        }
    }

    private struct Place {
        var x: CGFloat
        var y: CGFloat
        var size: CGSize
    }

    private func rows(_ subviews: Subviews, width: CGFloat) -> [[Place]] {
        var rows: [[Place]] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for view in subviews {
            var size = view.sizeThatFits(.unspecified)
            size.width = min(size.width, width)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + lineSpacing
                rowHeight = 0
            }
            if x == 0 { rows.append([]) }
            rows[rows.count - 1].append(Place(x: x, y: y, size: size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return rows
    }
}

/// A peach tag chip, "#bike", with an × to take it off when `remove` is given (CC03, CC06).
struct TagChip: View {
    let tag: String
    var remove: (() -> Void)?

    var body: some View {
        HStack(spacing: 4) {
            Text(verbatim: "#" + tag)
                .textStyle(.reviewChip)
                .lineLimit(1)
            if let remove {
                Button(action: remove) {
                    Icon.glyphClose.image
                        .resizable()
                        .frame(width: 14, height: 14)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Remove \("#" + tag)", bundle: .module, comment: "Tags sheet (P8.4 CC03): the × on a tag chip; the tag"))
            }
        }
        .foregroundStyle(ColorToken.textPrimary.color)
        .padding(.leading, 11)
        .padding(.trailing, remove == nil ? 11 : 2)
        .frame(minHeight: 32)
        .background(ReviewChipBlob().fill(ColorToken.accentPeach.color))
    }
}

// MARK: Tags sheet (P8.4 CC03)

/// Adds and removes a moment's tags; Cancel keeps them as they were.
struct TagEditorSheet: View {
    @Binding var tags: [String]
    /// Tags already used, most recent first: the suggestions.
    let recent: [String]
    @State private var draft: [String]
    @State private var text = ""
    @FocusState private var typing: Bool

    init(tags: Binding<[String]>, recent: [String]) {
        _tags = tags
        self.recent = recent
        _draft = State(initialValue: tags.wrappedValue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetBar(title: Text("Tags", bundle: .module)) { tags = draft }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    field
                    if let message = problemMessage {
                        message
                            .textStyle(.rowCaption)
                            .foregroundStyle(ColorToken.textSecondary.color)
                            .padding(.horizontal, 4)
                            .padding(.top, 8)
                    }
                    if !draft.isEmpty {
                        ChipFlow {
                            ForEach(draft, id: \.self) { tag in
                                TagChip(tag: tag) { draft.removeAll { $0 == tag } }
                            }
                        }
                        .padding(.top, 14)
                    }
                    if !suggestions.isEmpty {
                        Text("Suggested", bundle: .module, comment: "Tags sheet (P8.4 CC03): tags used before")
                            .textStyle(.labelCaps)
                            .foregroundStyle(ColorToken.textSecondary.color)
                            .accessibilityAddTraits(.isHeader)
                            .padding(.horizontal, 4)
                            .padding(.top, 22)
                        VStack(spacing: 0) {
                            ForEach(Array(suggestions.enumerated()), id: \.element) { index, tag in
                                suggestionRow(tag, isLast: index == suggestions.count - 1)
                            }
                        }
                        .background(ColorToken.surfaceCard.color, in: RoundedRectangle(cornerRadius: Radius.card))
                        .padding(.top, 8)
                    }
                    Text("Up to 10 tags. A tag helps you find this moment later.", bundle: .module, comment: "Tags sheet (P8.4 CC03): under the list")
                        .textStyle(.rowCaption)
                        .foregroundStyle(ColorToken.textTertiary.color)
                        .padding(.horizontal, 4)
                        .padding(.top, 14)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        .presentationBackground(ColorToken.surfaceSheet.color)
        .onAppear { typing = true }
    }

    private var field: some View {
        HStack(spacing: 8) {
            TextField(text: $text, prompt: Text("Add a tag", bundle: .module, comment: "Tags sheet (P8.4 CC03): the empty field")) {
                Text("Tag", bundle: .module)
            }
            .textStyle(.rowTitle)
            .foregroundStyle(ColorToken.textPrimary.color)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.done)
            .focused($typing)
            .onSubmit(add)
            .onChange(of: text) { if text.count > Tags.maxLength { text = String(text.prefix(Tags.maxLength)) } }
            .padding(.horizontal, 14)
            .frame(minHeight: 48)
            .background(FieldBlob().fill(ColorToken.surfaceCard.color))
            .accessibilityIdentifier("tags.field")
            Button(action: add) {
                Text("Add", bundle: .module)
                    .textStyle(.editorDone)
                    .foregroundStyle(problem == nil ? ColorToken.textOnCoral.color : ColorToken.textTertiary.color)
                    .padding(.horizontal, 18)
                    .frame(minHeight: 44)
                    .background(Capsule().fill(problem == nil ? ColorToken.actionCoral.color : ColorToken.surfaceChip.color))
            }
            .buttonStyle(.plain)
            .disabled(problem != nil)
            .accessibilityIdentifier("tags.add")
        }
    }

    private func suggestionRow(_ tag: String, isLast: Bool) -> some View {
        Button {
            draft = Tags.adding(tag, to: draft)
            text = ""
        } label: {
            HStack {
                Text(verbatim: "#" + tag)
                    .textStyle(.rowTitle)
                    .foregroundStyle(ColorToken.textPrimary.color)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Icon.glyphPlus.image
                    .frame(width: 20, height: 20)
                    .foregroundStyle(ColorToken.textPrimary.color)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 48)
            .overlay(alignment: .bottom) {
                if !isLast { ColorToken.separator.color.frame(height: 1).padding(.leading, 16) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(draft.count >= Tags.limit)
        .accessibilityLabel(Text("Add \("#" + tag)", bundle: .module, comment: "Tags sheet (P8.4 CC03): a suggested tag; the tag"))
    }

    private var problem: Tags.Problem? { Tags.problem(adding: text, to: draft) }

    /// Blank needs no words: Add is simply off.
    private var problemMessage: Text? {
        switch problem {
        case .duplicate: Text("This moment has that tag already.", bundle: .module, comment: "Tags sheet (P8.4 CC03): the typed tag is on the moment already")
        case .full: Text("You can add up to 10 tags.", bundle: .module, comment: "Tags sheet (P8.4 CC03): ten tags already")
        case .blank, nil: nil
        }
    }

    private var suggestions: [String] {
        Array(Tags.suggestions(text, from: recent, excluding: draft).prefix(6))
    }

    private func add() {
        guard problem == nil else { return }
        draft = Tags.adding(text, to: draft)
        text = ""
    }
}

// MARK: Mood sheet (P8.10 CC04)

/// One of five moods, or none; Cancel keeps the one there was.
struct MoodPickerSheet: View {
    @Binding var mood: Mood?
    @State private var draft: Mood?

    init(mood: Binding<Mood?>) {
        _mood = mood
        _draft = State(initialValue: mood.wrappedValue)
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetBar(title: Text("Mood", bundle: .module)) { mood = draft }
            VStack(spacing: 0) {
                ForEach(Mood.allCases, id: \.self) { mood in
                    row(mood, isLast: mood == Mood.allCases.last)
                }
            }
            .background(ColorToken.surfaceCard.color, in: RoundedRectangle(cornerRadius: Radius.card))
            .padding(.horizontal, 16)
            .padding(.top, 8)
            Button { draft = nil } label: {
                Text("Clear mood", bundle: .module, comment: "Mood sheet (P8.10 CC04): no mood on this moment")
                    .textStyle(.rowTitle)
                    .foregroundStyle(ColorToken.textLink.color)
                    .frame(minHeight: Size.minimumTapTarget)
            }
            .buttonStyle(.plain)
            .disabled(draft == nil)
            .opacity(draft == nil ? 0.4 : 1)
            .padding(.top, 14)
            .accessibilityIdentifier("mood.clear")
            Text("Only you set it. MimoDays never guesses your mood.", bundle: .module, comment: "Mood sheet (P8.10 CC04): under the list")
                .textStyle(.rowCaption)
                .foregroundStyle(ColorToken.textTertiary.color)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.top, 4)
            Spacer(minLength: 0)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        .presentationBackground(ColorToken.surfaceSheet.color)
    }

    private func row(_ mood: Mood, isLast: Bool) -> some View {
        Button { draft = mood } label: {
            HStack(spacing: 12) {
                Text(verbatim: mood.emoji)
                    .font(.system(size: 20))
                    .accessibilityHidden(true)
                mood.name
                    .textStyle(.rowTitle)
                    .foregroundStyle(ColorToken.textPrimary.color)
                Spacer(minLength: 8)
                if draft == mood {
                    Icon.glyphCheck.image
                        .frame(width: 20, height: 20)
                        .foregroundStyle(ColorToken.textLink.color)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 48)
            .overlay(alignment: .bottom) {
                if !isLast { ColorToken.separator.color.frame(height: 1).padding(.leading, 48) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(draft == mood ? .isSelected : [])
        .accessibilityIdentifier("mood.\(mood.rawValue)")
    }
}
