import Core
import DesignSystem
import Persistence
import SwiftUI

/// M08b: the kind, a span of days, voice note, written note and favourites. Changes apply as they're made;
/// the button shows how many moments are left and closes the sheet. Collection joins with collections (9.8).
struct SearchFiltersSheet: View {
    @Bindable var model: SearchModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.calendar) private var calendar
    /// The From or To row whose calendar is open.
    @State private var picking: Bound?
    @State private var picksTags = false
    @State private var picksMoods = false

    private enum Bound {
        case from
        case to
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Filters", bundle: .module)
                    .textStyle(.largeSheetTitle)
                    .foregroundStyle(ColorToken.textPrimary.color)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.horizontal, 4)
                SegmentedControl(selection: $model.filters.kind, options: [.all, .photos, .videos, .text]) { kind in
                    switch kind {
                    case .all: Text("All", bundle: .module)
                    case .photos: Text("Photos", bundle: .module)
                    case .videos: Text("Videos", bundle: .module)
                    case .text: Text("Text", bundle: .module)
                    }
                }
                .padding(.top, 16)
                .accessibilityIdentifier("filters.kind")
                card {
                    dateRow(.from)
                    dateRow(.to, isLast: true)
                }
                .padding(.top, 16)
                card {
                    toggleRow(Text("Has a voice note", bundle: .module), isOn: $model.filters.hasVoiceNote, id: "filters.voice")
                    toggleRow(Text("Has a written note", bundle: .module), isOn: $model.filters.hasWrittenNote, id: "filters.note")
                    toggleRow(Text("Favorites only", bundle: .module), isOn: $model.filters.favoritesOnly, id: "filters.favorites")
                    collectionRow
                    choiceRow(Text("Tags", bundle: .module), value: tagsValue, id: "filters.tags") { picksTags = true }
                    choiceRow(Text("Mood", bundle: .module), value: moodsValue, id: "filters.mood") { picksMoods = true }
                }
                .padding(.top, 12)
            }
            .padding(.horizontal, 16)
            .padding(.top, 24)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { buttons }
        .sheet(isPresented: $picksTags) {
            ChoiceListSheet(
                title: Text("Tags", bundle: .module), choices: model.tagChoices.map { (Tags.key($0), Text(verbatim: "#" + $0)) },
                empty: Text("No tags yet. Add them to a moment in Review or Edit moment.", bundle: .module, comment: "Search filters (P8.4 CC07): no moment has a tag"),
                selection: $model.filters.tags
            )
        }
        .sheet(isPresented: $picksMoods) {
            ChoiceListSheet(
                title: Text("Mood", bundle: .module), choices: Mood.allCases.map { ($0, $0.label) }, empty: Text(verbatim: ""),
                selection: $model.filters.moods
            )
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        .presentationBackground(ColorToken.surfaceSheet.color)
    }

    private var buttons: some View {
        HStack(spacing: 12) {
            Button { model.filters = SearchFilters(place: model.filters.place) } label: {
                Text("Reset", bundle: .module)
            }
            .buttonStyle(SoftButtonStyle())
            // 120 pt as drawn; a longer word or larger text widens it instead of breaking the word.
            .frame(minWidth: 120)
            .fixedSize(horizontal: true, vertical: false)
            .disabled(model.filters == SearchFilters(place: model.filters.place))
            .accessibilityIdentifier("filters.reset")
            Button { dismiss() } label: {
                Text("Show \(model.filteredCount) moments", bundle: .module)
            }
            .buttonStyle(.primary)
            .accessibilityIdentifier("filters.show")
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(ColorToken.surfaceSheet.color)
    }

    private func card(@ViewBuilder _ content: () -> some View) -> some View {
        VStack(spacing: 0, content: content)
            .background(ColorToken.surfaceCard.color, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    // MARK: Days

    @ViewBuilder
    private func dateRow(_ bound: Bound, isLast: Bool = false) -> some View {
        let key = bound == .from ? model.filters.from : model.filters.to
        Button {
            withAnimation(.snappy) { picking = picking == bound ? nil : bound }
        } label: {
            HStack(spacing: 8) {
                (bound == .from ? Text("From", bundle: .module) : Text("To", bundle: .module))
                    .textStyle(.rowTitle)
                    .foregroundStyle(ColorToken.textPrimary.color)
                Spacer(minLength: 8)
                Group {
                    if let key {
                        Text(MemoriesView.dayDate(key), format: Date.FormatStyle(date: .abbreviated, time: .omitted, timeZone: .gmt))
                    } else if bound == .from {
                        Text("Any time", bundle: .module)
                    } else {
                        Text("Today", bundle: .module)
                    }
                }
                .textStyle(.rowValue)
                .foregroundStyle(ColorToken.textTertiary.color)
                Icon.glyphChevron.image
                    .frame(width: 20, height: 20)
                    .foregroundStyle(ColorToken.textPrimary.color)
                    .rotationEffect(.degrees(picking == bound ? 90 : 0))
                    .flipsForRightToLeftLayoutDirection(true)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(bound == .from ? "filters.from" : "filters.to")
        if picking == bound {
            DatePicker(
                selection: dateBinding(bound), in: ...Date.now, displayedComponents: .date
            ) { bound == .from ? Text("From", bundle: .module) : Text("To", bundle: .module) }
                .datePickerStyle(.graphical)
                .tint(ColorToken.actionCoral.color)
                .padding(.horizontal, 8)
            if key != nil {
                Button {
                    if bound == .from { model.filters.from = nil } else { model.filters.to = nil }
                    picking = nil
                } label: {
                    bound == .from ? Text("Any time", bundle: .module) : Text("Up to today", bundle: .module)
                }
                .buttonStyle(.text)
                .padding(.bottom, 4)
            }
        }
        if !isLast {
            ColorToken.separator.color.frame(height: 1).padding(.leading, 16)
        }
    }

    /// The picker works in this device's days; the filter keeps yyyymmdd.
    private func dateBinding(_ bound: Bound) -> Binding<Date> {
        Binding {
            let key = (bound == .from ? model.filters.from : model.filters.to) ?? LocalDay(.now, in: calendar.timeZone).key
            return calendar.date(from: DateComponents(year: key / 10_000, month: key / 100 % 100, day: key % 100, hour: 12)) ?? .now
        } set: { date in
            let key = LocalDay(date, in: calendar.timeZone).key
            if bound == .from {
                model.filters.from = key
                if let to = model.filters.to, to < key { model.filters.to = key }
            } else {
                model.filters.to = key
                if let from = model.filters.from, from > key { model.filters.from = key }
            }
        }
    }

    // MARK: Collection

    /// Any, or one collection, picked from a menu.
    private var collectionRow: some View {
        Menu {
            Picker(selection: $model.filters.collection) {
                Text("Any", bundle: .module).tag(UUID?.none)
                ForEach(model.collections) { Text($0.title).tag(UUID?.some($0.id)) }
            } label: {
                Text("Collection", bundle: .module)
            }
        } label: {
            HStack(spacing: 8) {
                Text("Collection", bundle: .module)
                    .textStyle(.rowTitle)
                    .foregroundStyle(ColorToken.textPrimary.color)
                Spacer(minLength: 8)
                Group {
                    if let title = model.collections.first(where: { $0.id == model.filters.collection })?.title {
                        Text(title)
                    } else {
                        Text("Any", bundle: .module)
                    }
                }
                .textStyle(.rowValue)
                .foregroundStyle(ColorToken.textTertiary.color)
                .lineLimit(1)
                Icon.glyphChevron.image
                    .frame(width: 20, height: 20)
                    .foregroundStyle(ColorToken.textPrimary.color)
                    .flipsForRightToLeftLayoutDirection(true)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("filters.collection")
    }

    // MARK: Tags and mood (P8.4, P8.10 CC07)

    /// "Any", or the picked ones in the list's order.
    private var tagsValue: Text {
        let picked = model.tagChoices.filter { model.filters.tags.contains(Tags.key($0)) }
        return picked.isEmpty ? Text("Any", bundle: .module) : Text(verbatim: TagList.text(picked))
    }

    private var moodsValue: Text {
        let picked = Mood.allCases.filter(model.filters.moods.contains)
        guard let first = picked.first else { return Text("Any", bundle: .module) }
        return picked.dropFirst().reduce(first.label) { $0 + Text(verbatim: ", ") + $1.label }
    }

    private func choiceRow(_ title: Text, value: Text, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                title
                    .textStyle(.rowTitle)
                    .foregroundStyle(ColorToken.textPrimary.color)
                Spacer(minLength: 8)
                value
                    .textStyle(.rowValue)
                    .foregroundStyle(ColorToken.textTertiary.color)
                    .lineLimit(1)
                Icon.glyphChevron.image
                    .frame(width: 20, height: 20)
                    .foregroundStyle(ColorToken.textPrimary.color)
                    .flipsForRightToLeftLayoutDirection(true)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
            .overlay(alignment: .top) { ColorToken.separator.color.frame(height: 1).padding(.leading, 16) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(id)
    }

    // MARK: Switches

    private func toggleRow(_ title: Text, isOn: Binding<Bool>, id: String, isLast: Bool = false) -> some View {
        Toggle(isOn: isOn) {
            title
                .textStyle(.rowTitle)
                .foregroundStyle(ColorToken.textPrimary.color)
        }
        .tint(ColorToken.actionCoral.color)
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
        .overlay(alignment: .bottom) {
            if !isLast { ColorToken.separator.color.frame(height: 1).padding(.leading, 16) }
        }
        .accessibilityIdentifier(id)
    }
}

/// Any number of choices, ticked or not; each tap applies at once, like the other filters (CC07).
struct ChoiceListSheet<ID: Hashable>: View {
    let title: Text
    let choices: [(ID, Text)]
    /// Said when there is nothing to choose.
    let empty: Text
    @Binding var selection: Set<ID>
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TitleBar {
                EmptyView()
            } title: {
                title
                    .textStyle(.editorTitle)
                    .foregroundStyle(ColorToken.textPrimary.color)
                    .accessibilityAddTraits(.isHeader)
            } trailing: {
                Button { dismiss() } label: {
                    Text("Done", bundle: .module)
                        .textStyle(.editorDone)
                        .foregroundStyle(ColorToken.textLink.color)
                        .padding(.horizontal, 16)
                        .frame(minHeight: Size.minimumTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("sheet.done")
            }
            .padding(.top, 8)
            ScrollView {
                if choices.isEmpty {
                    empty
                        .textStyle(.rowCaption)
                        .foregroundStyle(ColorToken.textSecondary.color)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(choices.enumerated()), id: \.offset) { index, choice in
                            row(choice.0, choice.1, isLast: index == choices.count - 1)
                        }
                    }
                    .background(ColorToken.surfaceCard.color, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        .presentationBackground(ColorToken.surfaceSheet.color)
    }

    private func row(_ id: ID, _ label: Text, isLast: Bool) -> some View {
        let isOn = selection.contains(id)
        return Button {
            if isOn { selection.remove(id) } else { selection.insert(id) }
        } label: {
            HStack {
                label
                    .textStyle(.rowTitle)
                    .foregroundStyle(ColorToken.textPrimary.color)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if isOn {
                    Icon.glyphCheck.image
                        .frame(width: 20, height: 20)
                        .foregroundStyle(ColorToken.textLink.color)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 48)
            .overlay(alignment: .bottom) {
                if !isLast { ColorToken.separator.color.frame(height: 1).padding(.leading, 16) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
