import Core
import DesignSystem
import OSLog
import Persistence
import SwiftData
import SwiftUI

/// P05b's moments: every alive moment without coordinates, newest first, and the place chosen for some of them.
/// Nothing is looked up by itself - only search, recents and what the person picks (C11's sheet without the city).
@MainActor
@Observable
final class UnplacedModel: PlaceChoosing {
    private(set) var items: [MemoryItem] = []
    private(set) var place: ReviewPlace?
    private(set) var placeWasChosen = false
    let currentPlace: ReviewPlace? = nil
    let isLocating = false
    let nearby: [PlaceSuggestion] = []
    let tiles: MemoriesModel
    private let library: MediaLibrary
    private let places: PlaceServices
    private let logger = Logger(subsystem: "MimoDays", category: "Map")

    init(library: MediaLibrary, places: PlaceServices) {
        self.library = library
        self.places = places
        tiles = MemoriesModel(context: library.context, store: library.store, thumbnails: library.thumbnails)
    }

    func refresh() {
        var descriptor = FetchDescriptor<Moment>(predicate: #Predicate { $0.deletedAt == nil }, sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
        descriptor.relationshipKeyPathsForPrefetching = [\.location]
        do {
            items = try library.context.fetch(descriptor)
                .filter { $0.location?.latitude == nil || $0.location?.longitude == nil }
                .map {
                    MemoryItem(
                        id: $0.id, localDay: $0.localDay, capturedAt: $0.capturedAt, timeZoneID: $0.timeZoneID,
                        mediaType: $0.mediaType, origin: $0.origin, isFavorite: $0.isFavorite
                    )
                }
        } catch {
            logger.error("Reading moments without a place failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func choose(_ place: ReviewPlace?) {
        self.place = place
        placeWasChosen = true
    }

    func loadNearby() async {}

    func searchPlaces(_ text: String) async -> [PlaceSuggestion] {
        await places.lookup.search(text, near: nil)
    }

    func recentPlaces() -> [RecentPlace] {
        places.recents()
    }

    /// Gives the chosen place to these moments, then forgets the choice; false when there was none or saving failed.
    func applyChosenPlace(to ids: Set<UUID>) -> Bool {
        defer {
            place = nil
            placeWasChosen = false
        }
        guard let place, !ids.isEmpty else { return false }
        do {
            let moments = try library.context.fetch(FetchDescriptor<Moment>(predicate: #Predicate { ids.contains($0.id) }))
            for moment in moments {
                if let old = moment.location { library.context.delete(old) }
                moment.location = MomentLocation(
                    latitude: place.latitude, longitude: place.longitude, precision: place.precision, source: place.source, placeLabel: place.label
                )
            }
            try library.context.save()
            refresh()
            return true
        } catch {
            library.context.rollback()
            logger.error("Setting a place failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}

struct UnplacedScreen: View {
    @Environment(\.mediaLibrary) private var library
    @Environment(\.camera) private var camera

    var body: some View {
        if let library { UnplacedView(model: UnplacedModel(library: library, places: (camera ?? .simulated).places)) }
    }
}

/// P05b: moments without a place, all selectable; Set place gives the ticked ones one place by hand.
struct UnplacedView: View {
    @State var model: UnplacedModel
    @State private var selection: Set<UUID>?
    @State private var choosing = false

    init(model: UnplacedModel, selection: Set<UUID> = []) {
        _model = State(initialValue: model)
        _selection = State(initialValue: selection)
    }

    var body: some View {
        let chosen = selection ?? []
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Without a place", bundle: .module)
                    .textStyle(.pageTitle)
                    .foregroundStyle(ColorToken.textPrimary.color)
                    .accessibilityAddTraits(.isHeader)
                Text("Pick moments and give them a place by hand. Nothing is looked up automatically.", bundle: .module)
                    .textStyle(.pageIntro)
                    .foregroundStyle(ColorToken.textSecondary.color)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.trailing, 12)
                    .padding(.top, 6)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 3), spacing: 4) {
                    ForEach(model.items) { item in
                        SelectableTile(selection: $selection, id: item.id) {
                            MemoryTile(item: item, detail: model.tiles.details[item.id], image: model.tiles.images[item.id], leavesRoomForMark: true)
                        }
                        .accessibilityIdentifier("unplaced.tile")
                        .task { await model.tiles.load(item.id) }
                    }
                }
                .padding(.top, 20)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
            .frame(maxWidth: 1180)
            .frame(maxWidth: .infinity)
        }
        .background(ColorToken.canvas.color.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            SelectActionsBar(isEnabled: !chosen.isEmpty, inset: 20) {
                Button { choosing = true } label: {
                    HStack(spacing: 6) {
                        Icon.glyphPin.image.resizable().frame(width: 20, height: 20)
                            .foregroundStyle(ColorToken.textPrimary.color)
                            .accessibilityHidden(true)
                        Group {
                            if chosen.isEmpty {
                                Text("Set place", bundle: .module)
                            } else {
                                Text("Set place for \(chosen.count)", bundle: .module)
                            }
                        }
                        .textStyle(.editorDone)
                        .foregroundStyle(ColorToken.textLink.color)
                    }
                    .frame(maxWidth: .infinity, minHeight: Size.minimumTapTarget)
                    .contentShape(Rectangle())
                }
                .accessibilityIdentifier("unplaced.setPlace")
            }
        }
        .sheet(isPresented: $choosing, onDismiss: {
            if model.applyChosenPlace(to: chosen) { selection = [] }
        }) {
            PlaceSheet(model: model, showsCurrent: false)
        }
        .navigationTitle(Text("Without a place", bundle: .module))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(removing: .title)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                // Every tile is selectable here: the corner ticks them all, or none.
                let isAll = !model.items.isEmpty && chosen.count == model.items.count
                Button { selection = isAll ? [] : Set(model.items.map(\.id)) } label: {
                    (isAll ? Text("Deselect all", bundle: .module) : Text("Select all", bundle: .module))
                        .textStyle(.control)
                        .foregroundStyle(ColorToken.textLink.color)
                        .frame(minHeight: Size.minimumTapTarget)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("unplaced.selectAll")
            }
        }
        .task {
            model.refresh()
        }
    }
}
