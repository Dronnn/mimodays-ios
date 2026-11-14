import Core
import DesignSystem
import SwiftUI

/// M08b: the kind, a span of days, voice note, written note and favourites. Changes apply as they're made;
/// the button shows how many moments are left and closes the sheet. Collection joins with collections (9.8).
struct SearchFiltersSheet: View {
    @Bindable var model: SearchModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.calendar) private var calendar
    /// The From or To row whose calendar is open.
    @State private var picking: Bound?

    private enum Bound {
        case from
        case to
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Filters", bundle: .module)
                    .textStyle(.sheetTitle)
                    .foregroundStyle(ColorToken.textPrimary.color)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.horizontal, 4)
                SegmentedControl(selection: $model.filters.kind, options: [.all, .photos, .videos]) { kind in
                    switch kind {
                    case .all: Text("All", bundle: .module)
                    case .photos: Text("Photos", bundle: .module)
                    case .videos: Text("Videos", bundle: .module)
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
                    toggleRow(Text("Favorites only", bundle: .module), isOn: $model.filters.favoritesOnly, id: "filters.favorites", isLast: true)
                }
                .padding(.top, 12)
            }
            .padding(.horizontal, 16)
            .padding(.top, 24)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { buttons }
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
            .frame(maxWidth: 120)
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
                .textStyle(.rowCaption)
                .foregroundStyle(ColorToken.textSecondary.color)
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
