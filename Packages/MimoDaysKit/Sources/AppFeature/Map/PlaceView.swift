import Core
import DesignSystem
import MapKit
import SwiftUI

/// P03: one place - its name, how many moments and when, a strip of map around it, then its moments by month,
/// newest first. Select collects or deletes as in Memories; Make a movie opens Movies (Phase 11 takes the place).
struct PlaceView: View {
    let model: MapModel
    let id: String
    @Environment(\.mediaLibrary) private var library

    var body: some View {
        if let library, let place = model.place(id) {
            PlaceContent(place: place, image: model.images[place.moments.first?.id ?? UUID()], tiles: tiles(library))
        }
    }

    @MainActor
    private func tiles(_ library: MediaLibrary) -> MemoriesModel {
        MemoriesModel(context: library.context, store: library.store, thumbnails: library.thumbnails)
    }
}

private struct PlaceContent: View {
    let place: MapPlace
    let image: UIImage?
    @State var tiles: MemoriesModel
    @Environment(AppRouter.self) private var router
    @State private var selection: Set<UUID>?
    /// Pushed by item, as P03 itself is: a value link here would be dropped as soon as it lands.
    @State private var openMoment: MomentPager?

    init(place: MapPlace, image: UIImage?, tiles: MemoriesModel) {
        self.place = place
        self.image = image
        _tiles = State(initialValue: tiles)
    }

    /// Months (yyyymm), newest first, each with its moments newest first.
    private var months: [(key: Int, moments: [MapMoment])] {
        Dictionary(grouping: place.moments) { $0.item.localDay / 100 }
            .sorted { $0.key > $1.key }
            .map { (key: $0.key, moments: $0.value) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PlaceName(place: place)
                    .textStyle(.pageTitle)
                    .foregroundStyle(ColorToken.textPrimary.color)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.horizontal, 20)
                PlaceName.summary(place)
                    .textStyle(.pageIntro)
                    .foregroundStyle(ColorToken.textSecondary.color)
                    .padding(.horizontal, 20)
                    .padding(.top, 2)
                strip
                    .padding(.top, 10)
                ForEach(months, id: \.key) { month in
                    Text(MemoriesView.monthDate(month.key), format: Date.FormatStyle(timeZone: .gmt).month(.wide).year())
                        .textStyle(.labelCaps)
                        .foregroundStyle(ColorToken.textSecondary.color)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.horizontal, 22)
                        .padding(.top, 16)
                        .padding(.bottom, 2)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 3), spacing: 4) {
                        ForEach(month.moments) { moment in tile(moment) }
                    }
                    .padding(.horizontal, 20)
                }
            }
            .padding(.top, 4)
            .padding(.bottom, 24)
            .frame(maxWidth: 1180)
            .frame(maxWidth: .infinity)
        }
        .background(ColorToken.canvas.color.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if selection == nil { movieButton }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if selection != nil { SelectBar(selection: $selection, all: place.moments.map(\.id)) }
        }
        .memoriesSelectActions(model: tiles, selection: $selection)
        .navigationTitle(PlaceName.text(place))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(removing: .title)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar(selection == nil ? .visible : .hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { SelectButton(selection: $selection, id: "place.select") }
        }
        .navigationDestination(item: $openMoment) { MomentViewerScreen(pager: $0) }
        .task { tiles.refresh() }
    }

    /// `Map / Strip`: the place's own marker on the map around it; the map itself is on the Map tab.
    private var strip: some View {
        Map(initialPosition: .region(MKCoordinateRegion(center: place.coordinate, latitudinalMeters: 1200, longitudinalMeters: 1200)), interactionModes: []) {
            Annotation("", coordinate: place.coordinate) {
                MapMarker(image: image, count: place.moments.count, isSelected: false)
            }
            .annotationTitles(.hidden)
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .frame(height: 112)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func tile(_ moment: MapMoment) -> some View {
        let ids = place.moments.map(\.id)
        return Group {
            if selection != nil {
                SelectableTile(selection: $selection, id: moment.id) {
                    MemoryTile(item: moment.item, detail: tiles.details[moment.id], image: tiles.images[moment.id], leavesRoomForMark: true)
                }
            } else {
                Button { openMoment = MomentPager(ids: ids, start: moment.id) } label: {
                    MemoryTile(item: moment.item, detail: tiles.details[moment.id], image: tiles.images[moment.id])
                }
                .buttonStyle(.plain)
            }
        }
        .accessibilityIdentifier("place.tile")
        .task { await tiles.load(moment.id) }
    }

    /// `Button / Secondary`: a movie of this place.
    private var movieButton: some View {
        Button { router.open(.tab(.movies)) } label: {
            Label {
                Text("Make a movie of this place", bundle: .module)
            } icon: {
                Icon.glyphFilm.image.resizable().frame(width: 20, height: 20)
            }
        }
        .buttonStyle(SoftButtonStyle())
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .accessibilityIdentifier("place.movie")
    }
}
