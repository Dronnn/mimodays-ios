import Core
import DesignSystem
import SwiftData
import SwiftUI

/// Keeps search's model while it's on screen.
struct SearchScreen: View {
    @Environment(\.mediaLibrary) private var library

    var body: some View {
        if let library {
            SearchHost(model: SearchModel(library: library))
        }
    }
}

private struct SearchHost: View {
    @State var model: SearchModel

    var body: some View {
        SearchView(model: model)
    }
}

/// M08/M09: the field and Cancel, chips for the kind, voice notes and filters, then matching places and moments.
struct SearchView: View {
    @Bindable var model: SearchModel
    @Environment(\.dismiss) private var dismiss
    @State private var showsFilters = false
    @FocusState private var isFocused: Bool

    var body: some View {
        let hits = model.hits
        let places = model.places
        VStack(alignment: .leading, spacing: 0) {
            searchBar
                .padding(.top, 8)
            let findsNothing = model.isSearching && hits.isEmpty && places.isEmpty && model.isLoaded
            // With nothing found, only the filters that narrowed it stay (M09).
            chips(onlyActive: findsNothing && !model.filters.isEmpty)
                .padding(.top, 8)
            if !model.isSearching {
                Spacer()
            } else if findsNothing {
                noMatches
                    .padding(.top, 56)
                Spacer()
            } else {
                results(hits, places: places)
            }
        }
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity)
        .background(ColorToken.canvas.color.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .task {
            model.refresh()
            if !model.isSearching { isFocused = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in model.refresh() }
        .sheet(isPresented: $showsFilters) {
            SearchFiltersSheet(model: model)
        }
    }

    // MARK: Field and chips

    private var searchBar: some View {
        HStack(spacing: 14) {
            HStack(spacing: 8) {
                Icon.glyphSearch.image
                    .resizable()
                    .frame(width: 20, height: 20)
                    .accessibilityHidden(true)
                TextField(text: $model.query) {
                    Text("Search moments", bundle: .module).foregroundStyle(ColorToken.textTertiary.color)
                }
                .textStyle(.searchQuery)
                .tint(ColorToken.actionCoral.color)
                .focused($isFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .accessibilityIdentifier("search.field")
                if !model.query.isEmpty {
                    Button { model.query = "" } label: {
                        Icon.glyphClose.image
                            .resizable()
                            .frame(width: 11, height: 11)
                            .foregroundStyle(ColorToken.surfaceCard.color)
                            .frame(width: 18, height: 18)
                            .background(Circle().fill(ColorToken.textTertiary.color))
                            .frame(width: 32, height: Size.minimumTapTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Clear", bundle: .module))
                }
            }
            .foregroundStyle(ColorToken.textPrimary.color)
            .padding(.leading, 12)
            .padding(.trailing, 4)
            .frame(minHeight: 40)
            .background(FieldBlob().fill(ColorToken.surfaceChip.color))
            Button { dismiss() } label: {
                Text("Cancel", bundle: .module)
                    .textStyle(.searchCancel)
                    .foregroundStyle(ColorToken.textLink.color)
                    .frame(minHeight: Size.minimumTapTarget)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("search.cancel")
        }
        .padding(.horizontal, 16)
    }

    private func chips(onlyActive: Bool) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                if let place = model.filters.place {
                    SearchChip(icon: .glyphPin, title: Text(place), isOn: true, id: "search.chip.place") { model.filters.place = nil }
                        .accessibilityHint(Text("Removes this place", bundle: .module))
                }
                if !onlyActive || model.filters.kind == .photos {
                    SearchChip(title: Text("Photos", bundle: .module), isOn: model.filters.kind == .photos, id: "search.chip.photos") {
                        model.filters.kind = model.filters.kind == .photos ? .all : .photos
                    }
                }
                if !onlyActive || model.filters.kind == .videos {
                    SearchChip(title: Text("Videos", bundle: .module), isOn: model.filters.kind == .videos, id: "search.chip.videos") {
                        model.filters.kind = model.filters.kind == .videos ? .all : .videos
                    }
                }
                if !onlyActive || model.filters.hasVoiceNote {
                    SearchChip(icon: .glyphMic, title: Text("Voice", bundle: .module), isOn: model.filters.hasVoiceNote, id: "search.chip.voice") {
                        model.filters.hasVoiceNote.toggle()
                    }
                }
                let count = model.filters.count
                SearchChip(
                    icon: .glyphFilter,
                    title: count == 0 ? Text("Filters", bundle: .module) : Text("Filters · \(count)", bundle: .module),
                    isOn: count > 0, id: "search.filters"
                ) {
                    isFocused = false
                    showsFilters = true
                }
            }
            .padding(.horizontal, 16)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: Results

    private func results(_ hits: [SearchHit], places: [PlaceHit]) -> some View {
        let ids = hits.map(\.id)
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if !places.isEmpty {
                    sectionTitle(Text("Places", bundle: .module))
                        .padding(.top, 14)
                    VStack(spacing: 0) {
                        ForEach(Array(places.enumerated()), id: \.element.id) { index, place in
                            placeRow(place, isLast: index == places.count - 1)
                        }
                    }
                    .background(ColorToken.surfaceCard.color, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                }
                sectionTitle(Text("Moments · \(hits.count)", bundle: .module))
                    .padding(.top, places.isEmpty ? 14 : 24)
                ForEach(hits) { hit in
                    NavigationLink(value: MemoriesRoute.moment(MomentPager(ids: ids, start: hit.id))) {
                        resultRow(hit)
                    }
                    .buttonStyle(.plain)
                    .task { await model.load(hit.id) }
                }
            }
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.immediately)
    }

    private func sectionTitle(_ text: Text) -> some View {
        text
            .textStyle(.labelCaps)
            .foregroundStyle(ColorToken.textSecondary.color)
            .padding(.horizontal, 22)
            .accessibilityAddTraits(.isHeader)
    }

    private func placeRow(_ place: PlaceHit, isLast: Bool) -> some View {
        Button { model.show(place: place.label) } label: {
            HStack(spacing: 14) {
                Icon.glyphPin.image
                    .resizable()
                    .frame(width: 20, height: 20)
                    .frame(width: 36, height: 36)
                    .background(ColorToken.accentPeach.color, in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(place.label)
                        .textStyle(.rowTitle)
                    Group {
                        if place.latestYear == thisYear {
                            Text("\(place.count) moments", bundle: .module)
                        } else {
                            Text("Place detail: \(Text("\(place.count) moments", bundle: .module)) · \(String(place.latestYear))", bundle: .module)
                        }
                    }
                    .textStyle(.rowCaption)
                    .foregroundStyle(ColorToken.textTertiary.color)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Icon.glyphChevron.image
                    .frame(width: 20, height: 20)
                    .flipsForRightToLeftLayoutDirection(true)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(ColorToken.textPrimary.color)
            .padding(.leading, 14)
            .padding(.trailing, 12)
            .padding(.vertical, 12)
            .frame(minHeight: 64)
            .overlay(alignment: .bottom) {
                if !isLast { ColorToken.separator.color.frame(height: 1).padding(.leading, 64) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("search.place")
    }

    private func resultRow(_ hit: SearchHit) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Color(hex: 0xC9B8AA)
                .overlay {
                    if let image = model.images[hit.id] { Image(uiImage: image).resizable().scaledToFill() }
                }
                .frame(width: 76, height: 72)
                .clipShape(NoteThumbnailBlob())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                dayLabel(hit.entry.item.localDay)
                    .textStyle(.labelCaps)
                    .foregroundStyle(ColorToken.textSecondary.color)
                if let text = hit.text {
                    Text(text)
                        .textStyle(.reviewField)
                        .foregroundStyle(ColorToken.textPrimary.color)
                        .lineLimit(2)
                }
                if let field = hit.field {
                    matchLabel(field)
                        .textStyle(.searchMatch)
                        .foregroundStyle(ColorToken.textLink.color)
                }
            }
            .padding(.top, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(minHeight: 92, alignment: .top)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("search.result")
    }

    private func matchLabel(_ field: SearchField) -> Text {
        switch field {
        case .caption: Text("matched in caption", bundle: .module)
        case .note: Text("matched in note", bundle: .module)
        case .voiceNote: Text("matched in voice note", bundle: .module)
        case .place: Text("matched in place", bundle: .module)
        }
    }

    /// "SUN, OCT 18"; the year only when it isn't this one.
    private func dayLabel(_ key: Int) -> Text {
        var format = Date.FormatStyle(timeZone: .gmt).weekday(.abbreviated).month(.abbreviated).day()
        if key / 10_000 != thisYear { format = format.year() }
        return Text(MemoriesView.dayDate(key), format: format)
    }

    private var thisYear: Int { model.thisYear }

    // MARK: No matches (M09)

    private var noMatches: some View {
        VStack(spacing: 0) {
            ExplainerArt(glyph: .explainerSearch)
            Text("No matches", bundle: .module)
                .textStyle(.emptyTitle)
                .foregroundStyle(ColorToken.textPrimary.color)
                .padding(.top, 16)
                .accessibilityAddTraits(.isHeader)
            noMatchesMessage
                .textStyle(.emptyBody)
                .foregroundStyle(ColorToken.textBody.color)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
                .padding(.horizontal, 58)
            if !model.filters.isEmpty {
                Button { model.clearFilters() } label: {
                    Text("Search all moments", bundle: .module)
                }
                .buttonStyle(SoftButtonStyle())
                .padding(.horizontal, 20)
                .padding(.top, 21)
                .accessibilityIdentifier("search.all")
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var noMatchesMessage: Text {
        let query = model.query.trimmingCharacters(in: .whitespacesAndNewlines)
        let first: Text = switch (query.isEmpty, model.filters.count == 1 ? model.filters.kind : nil) {
        case (true, _): Text("No moments match these filters.", bundle: .module)
        case (false, .photos): Text("Nothing matches “\(query)” in photos.", bundle: .module)
        case (false, .videos): Text("Nothing matches “\(query)” in videos.", bundle: .module)
        case (false, _) where model.filters.isEmpty: Text("Nothing matches “\(query)”.", bundle: .module)
        case (false, _): Text("Nothing matches “\(query)” with these filters.", bundle: .module)
        }
        return Text("No matches message: \(first) \(Text("Search looks at notes, voice-note words and places.", bundle: .module))", bundle: .module)
    }
}

/// `Chip / Search`: a label, maybe a glyph, on a hand-cut chip; peach with coral words when on.
struct SearchChip: View {
    var icon: Icon?
    let title: Text
    let isOn: Bool
    let id: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon {
                    icon.image
                        .resizable()
                        .frame(width: 16, height: 16)
                        .accessibilityHidden(true)
                }
                title
                    .textStyle(isOn ? .reviewChipOn : .reviewChip)
                    .lineLimit(1)
            }
            .foregroundStyle((isOn ? ColorToken.textLink : .textPrimary).color)
            .padding(.leading, icon == nil ? 14 : 12)
            .padding(.trailing, 14)
            .frame(minHeight: 34)
            .background(ReviewChipBlob().fill((isOn ? ColorToken.accentPeach : .surfaceChip).color))
            .frame(minHeight: Size.minimumTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .accessibilityIdentifier(id)
    }
}

/// A quiet full-width button on a hand-cut chip-coloured shape ("Search all moments", "Reset").
struct SoftButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .textStyle(.rowTitle)
            .foregroundStyle(ColorToken.textPrimary.color)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background { ColorToken.surfaceChip.color.mask { Icon.shapeButton.image.resizable() } }
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Rectangle())
    }
}
