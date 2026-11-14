import Core
import DesignSystem
import Persistence
import SwiftData
import SwiftUI

/// P04 "Show on the map": All time / This year / Custom (From, To), Photos & videos / Photos / Videos, Favorites only
/// and a collection. Changes apply as they're made; the button says how many moments are left and closes.
struct MapFiltersSheet: View {
    @Bindable var model: MapModel
    let thisYear: Int
    @Environment(\.dismiss) private var dismiss
    @Environment(\.calendar) private var calendar
    @State private var collections: [MomentCollection] = []
    @State private var picking: Bound?
    /// Custom stays chosen while its days are still empty.
    @State private var customChosen = false

    private enum Bound {
        case from
        case to
    }

    private var period: Binding<MapFilters.Period> {
        Binding {
            customChosen ? .custom : model.filters.period(thisYear: thisYear)
        } set: { period in
            customChosen = period == .custom
            switch period {
            case .allTime: (model.filters.from, model.filters.to) = (nil, nil)
            case .thisYear: (model.filters.from, model.filters.to) = (thisYear * 10_000 + 101, nil)
            case .custom: picking = .from
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Show on the map", bundle: .module)
                    .textStyle(.sheetTitle)
                    .foregroundStyle(ColorToken.textPrimary.color)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.horizontal, 4)
                SegmentedControl(selection: period, options: [.allTime, .thisYear, .custom]) { period in
                    switch period {
                    case .allTime: Text("All time", bundle: .module)
                    case .thisYear: Text("This year", bundle: .module)
                    case .custom: Text("Custom", bundle: .module)
                    }
                }
                .padding(.top, 16)
                .accessibilityIdentifier("mapFilters.period")
                if period.wrappedValue == .custom {
                    card {
                        dateRow(.from)
                        dateRow(.to, isLast: true)
                    }
                    .padding(.top, 12)
                }
                SegmentedControl(selection: $model.filters.kind, options: [.all, .photos, .videos]) { kind in
                    switch kind {
                    case .all: Text("Photos & videos", bundle: .module)
                    case .photos: Text("Photos", bundle: .module)
                    case .videos: Text("Videos", bundle: .module)
                    }
                }
                .padding(.top, 20)
                .accessibilityIdentifier("mapFilters.kind")
                card {
                    Toggle(isOn: $model.filters.favoritesOnly) {
                        Text("Favorites only", bundle: .module).textStyle(.rowTitle).foregroundStyle(ColorToken.textPrimary.color)
                    }
                    .tint(ColorToken.actionCoral.color)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 52)
                    .accessibilityIdentifier("mapFilters.favorites")
                    ColorToken.separator.color.frame(height: 1).padding(.leading, 16)
                    collectionRow
                }
                .padding(.top, 14)
            }
            .padding(.horizontal, 16)
            .padding(.top, 24)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { buttons }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        .presentationBackground(ColorToken.surfaceSheet.color)
        .task {
            collections = (try? model.library.context.fetch(FetchDescriptor<MomentCollection>(sortBy: [SortDescriptor(\.sortOrder)]))) ?? []
            customChosen = model.filters.period(thisYear: thisYear) == .custom
        }
    }

    private var buttons: some View {
        HStack(spacing: 12) {
            Button {
                model.filters = MapFilters()
                customChosen = false
                picking = nil
            } label: { Text("Reset", bundle: .module) }
                .buttonStyle(SoftButtonStyle())
                .frame(maxWidth: 120)
                .disabled(model.filters.isEmpty && !customChosen)
                .accessibilityIdentifier("mapFilters.reset")
            Button { dismiss() } label: { Text("Show \(model.filtered.count) moments", bundle: .module) }
                .buttonStyle(.primary)
                .accessibilityIdentifier("mapFilters.show")
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(ColorToken.surfaceSheet.color)
    }

    private var collectionRow: some View {
        Menu {
            Picker(selection: $model.filters.collection) {
                Text("Any collection", bundle: .module).tag(UUID?.none)
                ForEach(collections) { collection in
                    Text(collection.title).tag(UUID?.some(collection.id))
                }
            } label: {
                Text("Collection", bundle: .module)
            }
        } label: {
            HStack(spacing: 8) {
                Text("Collection", bundle: .module).textStyle(.rowTitle).foregroundStyle(ColorToken.textPrimary.color)
                Spacer(minLength: 8)
                Group {
                    if let id = model.filters.collection, let collection = collections.first(where: { $0.id == id }) {
                        Text(collection.title)
                    } else {
                        Text("Any collection", bundle: .module)
                    }
                }
                .textStyle(.rowCaption)
                .foregroundStyle(ColorToken.textSecondary.color)
                .lineLimit(1)
                Icon.glyphChevron.image
                    .resizable()
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
        .accessibilityIdentifier("mapFilters.collection")
    }

    private func card(@ViewBuilder _ content: () -> some View) -> some View {
        VStack(spacing: 0, content: content)
            .background(ColorToken.surfaceCard.color, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

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
                    .resizable()
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
        .accessibilityIdentifier(bound == .from ? "mapFilters.from" : "mapFilters.to")
        if picking == bound {
            DatePicker(selection: dateBinding(bound), in: ...Date.now, displayedComponents: .date) {
                bound == .from ? Text("From", bundle: .module) : Text("To", bundle: .module)
            }
            .datePickerStyle(.graphical)
            .tint(ColorToken.actionCoral.color)
            .padding(.horizontal, 8)
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
}
