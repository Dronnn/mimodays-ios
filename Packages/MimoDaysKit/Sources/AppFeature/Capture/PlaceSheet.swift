import Core
import DesignSystem
import SwiftUI

/// What `PlaceSheet` reads and sets.
@MainActor
protocol PlaceChoosing: AnyObject, Observable {
    var place: ReviewPlace? { get }
    /// A place or "No place" was picked.
    var placeWasChosen: Bool { get }
    /// This iPhone's city now; nil when it isn't offered.
    var currentPlace: ReviewPlace? { get }
    var isLocating: Bool { get }
    var nearby: [PlaceSuggestion] { get }
    func choose(_ place: ReviewPlace?)
    func loadNearby() async
    func searchPlaces(_ text: String) async -> [PlaceSuggestion]
    func recentPlaces() -> [RecentPlace]
}

extension ReviewModel: PlaceChoosing {}

/// `Sheet / Place` (C11): search, then the current city, places nearby, places used before, and No place.
/// Without location access the current and nearby rows are left out; the rest still works.
/// Review (C11) and Edit moment (M07) both choose with it.
struct PlaceSheet<Model: PlaceChoosing>: View {
    let model: Model
    let showsCurrent: Bool
    @State private var query = ""
    @State private var results: [PlaceSuggestion]?
    @State private var recents: [RecentPlace]
    @State private var height: CGFloat = 470
    @State private var detent = PresentationDetent.height(470)
    @FocusState private var searches: Bool
    @Environment(\.dismiss) private var dismiss

    init(model: Model, showsCurrent: Bool) {
        self.model = model
        self.showsCurrent = showsCurrent
        _recents = State(initialValue: model.recentPlaces())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Place", bundle: .module)
                .textStyle(.sheetTitle)
                .foregroundStyle(ColorToken.textPrimary.color)
                .accessibilityAddTraits(.isHeader)
                .padding(.horizontal, 4)
            searchField
                .padding(.top, 13)
            if query.isEmpty {
                card { suggestions }
                    .padding(.top, 14)
                Text("Places are stored on this iPhone only. You can choose how precise they are in Settings.", bundle: .module)
                    .textStyle(.rowCaption)
                    .foregroundStyle(ColorToken.textTertiary.color)
                    .padding(.horizontal, 8)
                    .padding(.top, 14)
            } else {
                ScrollView {
                    searchResults.padding(.top, 14)
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 24)
        .padding(.bottom, 8)
        .frame(maxHeight: query.isEmpty ? nil : .infinity, alignment: .top)
        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { if query.isEmpty { height = $0 } }
        .presentationDetents([.height(height), .large], selection: $detent)
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        .presentationBackground(ColorToken.surfaceSheet.color)
        .onChange(of: height) { if detent != .large { detent = .height(height) } }
        .onChange(of: searches) { if searches { detent = .large } }
        .task(id: model.currentPlace) { await model.loadNearby() }
        .task(id: query) {
            results = nil
            let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            results = await model.searchPlaces(text)
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Icon.glyphSearch.image
                .frame(width: 24, height: 24)
                .foregroundStyle(ColorToken.textPrimary.color)
                .accessibilityHidden(true)
            TextField(text: $query) {
                Text("Search places", bundle: .module).foregroundStyle(ColorToken.textTertiary.color)
            }
            .textStyle(.searchField)
            .foregroundStyle(ColorToken.textPrimary.color)
            .tint(ColorToken.actionCoral.color)
            .focused($searches)
            .submitLabel(.search)
            .autocorrectionDisabled()
            .accessibilityIdentifier("place.search")
        }
        .padding(.leading, 14)
        .padding(.trailing, 16)
        .frame(minHeight: 44)
        .background(FieldBlob().fill(ColorToken.surfaceCard.color))
    }

    @ViewBuilder
    private var suggestions: some View {
        let nearby = showsCurrent ? model.nearby : []
        let shown = Set([model.currentPlace?.label].compactMap(\.self) + nearby.map(\.name))
        if showsCurrent, model.currentPlace != nil || model.isLocating {
            let current = model.currentPlace
            row(
                icon: .glyphPin,
                title: current.map { $0.label.map { Text($0) } ?? Text("Current location", bundle: .module) }
                    ?? Text("Finding where you are…", bundle: .module),
                detail: Text("Current location · city only", bundle: .module),
                isSelected: current != nil && model.place == current,
                id: "place.current"
            ) {
                if let current { pick(current) }
            }
            .disabled(current == nil)
        }
        ForEach(nearby) { suggestion in
            row(icon: .glyphPin, title: Text(suggestion.name), detail: Text("Nearby", bundle: .module),
                isSelected: model.place == .picked(suggestion), id: "place.nearby") {
                pick(.picked(suggestion))
            }
        }
        ForEach(recents.filter { !shown.contains($0.id) }) { recent in
            row(icon: .glyphClock, title: Text(recent.id), detail: Text("Used \(recent.uses) times", bundle: .module),
                isSelected: model.place == recent.place, id: "place.recent") {
                pick(recent.place)
            }
        }
        row(icon: .glyphClose, title: Text("No place", bundle: .module), detail: nil,
            isSelected: model.place == nil && model.placeWasChosen, id: "place.none", isLast: true) {
            pick(nil)
        }
    }

    @ViewBuilder
    private var searchResults: some View {
        if let results {
            if results.isEmpty {
                Text("No places found", bundle: .module)
                    .textStyle(.rowCaption)
                    .foregroundStyle(ColorToken.textTertiary.color)
                    .padding(.horizontal, 8)
                    .accessibilityIdentifier("place.noResults")
            } else {
                card {
                    ForEach(Array(results.enumerated()), id: \.element.id) { index, suggestion in
                        row(icon: .glyphPin, title: Text(suggestion.name), detail: suggestion.detail.map { Text($0) },
                            isSelected: model.place == .picked(suggestion), id: "place.result", isLast: index == results.count - 1) {
                            pick(.picked(suggestion))
                        }
                    }
                }
            }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.top, 20)
        }
    }

    private func card(@ViewBuilder _ content: () -> some View) -> some View {
        VStack(spacing: 0, content: content)
            .background(ColorToken.surfaceCard.color, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    /// A 64 pt row: peach disc with a glyph, title and detail, a coral check when chosen, a chevron otherwise.
    private func row(
        icon: Icon, title: Text, detail: Text?, isSelected: Bool, id: String, isLast: Bool = false, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                icon.image
                    .frame(width: 20, height: 20)
                    .foregroundStyle(ColorToken.textPrimary.color)
                    .frame(width: 36, height: 36)
                    .background(ColorToken.accentPeach.color, in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    title
                        .textStyle(.rowTitle)
                        .foregroundStyle(ColorToken.textPrimary.color)
                    if let detail {
                        detail
                            .textStyle(.rowCaption)
                            .foregroundStyle(ColorToken.textTertiary.color)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Group {
                    if isSelected {
                        Icon.glyphCheck.image.frame(width: 24, height: 24).foregroundStyle(ColorToken.textLink.color)
                    } else {
                        Icon.glyphChevron.image.frame(width: 20, height: 20).foregroundStyle(ColorToken.textPrimary.color)
                            .flipsForRightToLeftLayoutDirection(true)
                    }
                }
                .accessibilityHidden(true)
            }
            .padding(.leading, 14)
            .padding(.trailing, 12)
            .padding(.vertical, 12)
            .frame(minHeight: 64)
            .overlay(alignment: .bottom) {
                if !isLast {
                    ColorToken.separator.color.frame(height: 1).padding(.leading, 64)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(id)
    }

    private func pick(_ place: ReviewPlace?) {
        model.choose(place)
        dismiss()
    }
}
