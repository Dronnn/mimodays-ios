import Core
import DesignSystem
import SwiftData
import SwiftUI

/// Screens pushed from the Map tab.
enum MapRoute: Hashable {
    /// P03.
    case place(String)
    /// P05b.
    case unplaced
    /// Every place as a list (the map's accessible alternative).
    case places
}

struct MapScreen: View {
    @Environment(\.mediaLibrary) private var library
    var body: some View {
        if let library { MapHost(model: MapModel(library: library)) }
    }
}

private struct MapHost: View {
    @State var model: MapModel
    var body: some View { MapView(model: model) }
}

/// P01: the title, filters and settings, the date chip, the map with photo markers and Recent places.
/// P02 opens on a place; P05 replaces the map before any moment has a place; P06 when the map can't load.
struct MapView: View {
    let model: MapModel
    @Environment(AppRouter.self) private var router
    @Environment(\.permissions) private var permissions
    @State private var asker = PermissionAsker()
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.calendar) private var calendar
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var selection: String?
    @State private var filtering = false
    @State private var fitToken = 0
    @State private var failed = false
    @State private var retry = 0
    @State private var location = PermissionStatus.notDetermined
    @State private var showsUser = false
    /// How much of the map the places panel covers at its strip height, from the map's bottom edge (iPhone).
    @State private var panelCover: CGFloat = 0
    @State private var openMoment: MomentPager?
    /// P03, from P02's See all: the sheet isn't part of this stack, so the map pushes it.
    @State private var shownPlace: String?

    private var thisYear: Int { LocalDay(.now, in: calendar.timeZone).key / 10_000 }

    private static let panelWidth: CGFloat = 360

    /// X03: on iPad the map fills the screen and the places float over it in a panel on the left.
    private var isWide: Bool { sizeClass == .regular }
    private var showsMap: Bool { model.isLoaded && model.hasLocatedMoments && !failed }

    var body: some View {
        Group {
            if isWide, showsMap {
                widePage
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    content
                }
            }
        }
        .background(ColorToken.canvas.color.ignoresSafeArea())
        .permissionExplainers(asker)
        .navigationTitle(Text("Map", bundle: .module))
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(for: MapRoute.self) { route in
            switch route {
            case let .place(id): PlaceView(model: model, id: id)
            case .unplaced: UnplacedScreen()
            case .places: PlacesListView(model: model)
            }
        }
        .navigationDestination(item: $openMoment) { MomentViewerScreen(pager: $0) }
        .navigationDestination(item: $shownPlace) { PlaceView(model: model, id: $0) }
        .memoriesDestinations(thisYear: thisYear)
        .sheet(item: Binding(get: { isWide ? nil : selection.flatMap(model.place) }, set: { selection = $0?.id })) { place in
            PlacePreviewSheet(model: model, place: place) { pager in
                selection = nil
                openMoment = pager
            } seeAll: {
                selection = nil
                shownPlace = place.id
            }
        }
        .sheet(isPresented: $filtering) { MapFiltersSheet(model: model, thisYear: thisYear) }
        .task {
            model.refresh()
            fitToken += 1
            location = await permissions.status(of: .location)
        }
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in model.refresh() }
        .onChange(of: model.filters) { fitToken += 1 }
        .onChange(of: panelCover) { fitToken += 1 }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { location = await permissions.status(of: .location) }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Spacer()
                circleButton(.glyphFilter, Text("Filters", bundle: .module), id: "map.filters") { filtering = true }
                circleButton(.glyphGear, Text("Settings", bundle: .module), id: "settings") { router.open(.settings) }
            }
            .padding(.trailing, 19)
            title
                .padding(.leading, 23)
            // P05 keeps the chip too: the map's period is there before any place is.
            Button { filtering = true } label: { dateChip }
                .buttonStyle(.plain)
                .padding(.leading, 20)
                .padding(.top, 16)
                .accessibilityIdentifier("map.period")
        }
        .statusBarLift(9, compactOnly: false)
        .padding(.bottom, 12)
    }

    /// "Map" with its brush underline and star.
    private var title: some View {
        Text("Map", bundle: .module)
                .textStyle(.screenTitle)
                .foregroundStyle(ColorToken.textPrimary.color)
                .overlay(alignment: .bottomLeading) {
                    Icon.markBrush.image
                        .resizable()
                        .frame(width: 78, height: 10.5)
                        .foregroundStyle(ColorToken.actionCoral.color)
                        .offset(x: 3, y: 10)
                        .accessibilityHidden(true)
                }
                .overlay(alignment: .topTrailing) {
                    Icon.markStarSolo.image
                        .resizable()
                        .frame(width: 28, height: 28.9)
                        .foregroundStyle(ColorToken.accentApricot.color)
                        .offset(x: 33, y: -4)
                        .accessibilityHidden(true)
                }
                .accessibilityAddTraits(.isHeader)
    }

    private func circleButton(_ icon: Icon, _ label: Text, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            icon.image
                .resizable()
                .frame(width: 22, height: 22)
                .foregroundStyle(ColorToken.textPrimary.color)
                .frame(width: 40, height: 40)
                .overlay(Circle().strokeBorder(ColorToken.textPrimary.color, lineWidth: 1.3))
                .frame(width: Size.minimumTapTarget, height: Size.minimumTapTarget)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }

    /// "All time", "This year", "Jun 1 – Aug 31, 2026"; " · 2" more when other filters are on.
    private var dateChip: some View {
        HStack(spacing: 6) {
            Icon.glyphCalendar.image.resizable().frame(width: 16, height: 16).accessibilityHidden(true)
            periodText.textStyle(.reviewChip)
            let others = model.filters.count - (model.filters.from == nil ? 0 : 1) - (model.filters.to == nil ? 0 : 1)
            if others > 0 {
                Text(verbatim: "·").textStyle(.reviewChip)
                Text("\(others) filters", bundle: .module).textStyle(.reviewChip)
            }
        }
        .foregroundStyle(ColorToken.textPrimary.color)
        .padding(.horizontal, 12)
        .frame(minHeight: 34)
        .background(ReviewChipBlob().fill(ColorToken.surfaceChip.color))
        .frame(minHeight: Size.minimumTapTarget)
        .contentShape(Rectangle())
    }

    private var periodText: Text {
        switch model.filters.period(thisYear: thisYear) {
        case .allTime: return Text("All time", bundle: .module)
        case .thisYear: return Text("This year", bundle: .module)
        case .custom:
            let format = Date.FormatStyle(date: .abbreviated, time: .omitted, timeZone: .gmt)
            let from = model.filters.from.map { Text(MemoriesView.dayDate($0), format: format) } ?? Text("Any time", bundle: .module)
            let to = model.filters.to.map { Text(MemoriesView.dayDate($0), format: format) } ?? Text("Today", bundle: .module)
            return Text("Map period: \(from) – \(to)", bundle: .module)
        }
    }

    // MARK: X03

    private var widePage: some View {
        mapCanvas
            .ignoresSafeArea(edges: [.bottom, .trailing])
            .overlay(alignment: .topTrailing) {
                VStack(alignment: .trailing, spacing: 12) {
                    circleButton(.glyphGear, Text("Settings", bundle: .module), id: "settings") { router.open(.settings) }
                        .background(Circle().fill(ColorToken.mediaFrame.color).padding(2))
                    locateButton
                }
                .padding(.top, 12)
                .padding(.trailing, 16)
            }
            .overlay {
                if model.places.isEmpty { nothingMatches }
            }
            .overlay(alignment: .topLeading) { placesPanel }
    }

    /// The panel: the title, the period and filters, the chosen place, every place.
    private var placesPanel: some View {
        // As tall as its content; a scroll view only once that is taller than the screen.
        ViewThatFits(in: .vertical) {
            panelContent
            ScrollView { panelContent }.scrollBounceBehavior(.basedOnSize)
        }
        .frame(width: Self.panelWidth)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(ColorToken.surfaceSheet.color)
                .shadow(color: Color(hex: 0x4B2938).opacity(0.14), radius: 14, y: 4)
        )
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .padding(16)
        .padding(.bottom, 8)
    }

    private var panelContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            title
                .padding(.leading, 4)
            HStack(spacing: 8) {
                Button { filtering = true } label: { dateChip }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("map.period")
                Button { filtering = true } label: { filtersChip }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("map.filters")
            }
            .padding(.top, 14)
            if let place = selection.flatMap(model.place) {
                PlacePreview(model: model, place: place) { pager in
                    openMoment = pager
                } seeAll: {
                    shownPlace = place.id
                } close: {
                    selection = nil
                }
                .padding(.top, 22)
                .id(place.id)
            }
            PlacesList(model: model)
                .padding(.horizontal, -16)
                .padding(.top, 24)
        }
        .padding(.horizontal, 20)
        .padding(.top, 22)
        .padding(.bottom, 20)
    }

    private var filtersChip: some View {
        HStack(spacing: 6) {
            Icon.glyphFilter.image.resizable().frame(width: 16, height: 16).accessibilityHidden(true)
            Text("Filters", bundle: .module).textStyle(.reviewChip)
        }
        .foregroundStyle(ColorToken.textPrimary.color)
        .padding(.horizontal, 12)
        .frame(minHeight: 34)
        .background(ReviewChipBlob().fill(ColorToken.surfaceChip.color))
        .frame(minHeight: Size.minimumTapTarget)
        .contentShape(Rectangle())
    }

    private var mapCanvas: some View {
        MapCanvas(
            places: model.places, images: model.images, selection: $selection, fitToken: fitToken, showsUser: showsUser,
            cover: isWide ? EdgeInsets(top: 0, leading: Self.panelWidth + 16, bottom: 0, trailing: 0)
                : EdgeInsets(top: 0, leading: 0, bottom: panelCover, trailing: 0),
            onLoad: { id in Task { await model.load(id) } }, onFailure: { failed = true }
        )
        .id(retry)
    }

    // MARK: Map

    @ViewBuilder
    private var content: some View {
        if !model.isLoaded {
            Color.clear
        } else if !model.hasLocatedMoments {
            noPlaces
        } else if failed {
            cannotLoad
        } else {
            mapCanvas
            .ignoresSafeArea(edges: .bottom)
            .overlay(alignment: .topTrailing) { locateButton.padding(.top, 12).padding(.trailing, 16) }
            .overlay(alignment: .bottom) { RecentPlacesPanel(model: model, cover: $panelCover) { selection = $0 } }
            .overlay {
                if model.places.isEmpty { nothingMatches }
            }
        }
    }

    private var locateButton: some View {
        Button { Task { await locate() } } label: {
            Icon.glyphLocate.image
                .resizable()
                .frame(width: 22, height: 22)
                .foregroundStyle(ColorToken.textPrimary.color)
                .frame(width: 44, height: 44)
                .background(Circle().fill(ColorToken.mediaFrame.color).shadow(color: Color(hex: 0x4B2938).opacity(0.16), radius: 5, y: 2))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(showsUser ? Text("Show all places", bundle: .module) : Text("Show where I am", bundle: .module))
        .accessibilityIdentifier("map.locate")
    }

    /// Where I am when location is allowed (asking first if it never was); otherwise, or a second tap, all places.
    private func locate() async {
        if showsUser {
            showsUser = false
            fitToken += 1
            return
        }
        if location == .notDetermined { location = await asker.request(.location, using: permissions) }
        if location.isUsable {
            showsUser = true
        } else {
            fitToken += 1
        }
    }

    private var nothingMatches: some View {
        VStack(spacing: 10) {
            Text("No places match these filters.", bundle: .module)
                .textStyle(.rowTitle)
                .foregroundStyle(ColorToken.textPrimary.color)
                .multilineTextAlignment(.center)
            Button { model.filters = MapFilters() } label: { Text("Reset", bundle: .module) }
                .buttonStyle(.text)
                .accessibilityIdentifier("map.resetFilters")
        }
        .padding(20)
        .background(FieldBlob().fill(ColorToken.surfaceCard.color))
        .padding(.horizontal, 40)
    }

    // MARK: P05

    /// No moment has a place yet: the map stays, veiled, under a card saying what it is for and how to get there.
    private var noPlaces: some View {
        ZStack(alignment: .top) {
            MapCanvas(places: [], images: [:], selection: .constant(nil), fitToken: 0, showsUser: false, onLoad: { _ in }, onFailure: {})
                .overlay(Color(hex: 0xF3E8DE).opacity(0.55))
                .ignoresSafeArea(edges: .bottom)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            ScrollView {
                NoPlacesCard(locationIsUsable: location.isUsable, unlocatedCount: model.unlocatedCount) {
                    Task { await turnOnLocation() }
                }
                    .frame(maxWidth: 420)
                    .padding(.horizontal, 24)
                    .padding(.top, 44)
                    .padding(.bottom, 24)
                    .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private func turnOnLocation() async {
        if location == .notDetermined {
            location = await asker.request(.location, using: permissions)
        } else if let url = URL(string: UIApplication.openSettingsURLString) {
            openURL(url)
        }
    }

    // MARK: P06

    /// The map didn't load: say so plainly and list every place instead.
    private var cannotLoad: some View {
        MapUnavailableView(model: model) {
            failed = false
            retry += 1
            fitToken += 1
        }
    }
}

/// P01's sheet: recent places, newest visit first; All places lists every one. It rises from the screen's bottom edge,
/// under the tab bar, and its grabber drags it between three heights: just the title, the photo strip, and half the
/// screen with every recent place (Andrew, 2026-11-16).
struct RecentPlacesPanel: View {
    enum Detent: Int, CaseIterable {
        case collapsed
        case strip
        case half
    }

    let model: MapModel
    /// The strip's height plus the tab bar under it: what the map keeps its places clear of.
    @Binding var cover: CGFloat
    let select: (String) -> Void
    @State private var detent = Detent.strip
    @State private var dragOffset: CGFloat = 0
    @State private var headerHeight: CGFloat = 60
    @State private var stripHeight: CGFloat = 120
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// A place's column, 108 pt as drawn; it widens with larger text so names keep whole words.
    @ScaledMetric(relativeTo: .footnote) private var width: CGFloat = 108
    /// P01 draws each photo with its own uneven outline; places cycle through them.
    private static let photoShapes = [AnyShape(PlacePhotoBlobA()), AnyShape(PlacePhotoBlobB()), AnyShape(PlacePhotoBlobC())]

    var body: some View {
        GeometryReader { proxy in
            let bottom = proxy.safeAreaInsets.bottom
            let heights = heights(screen: proxy.size.height + proxy.safeAreaInsets.top + bottom)
            let resting = heights[detent.rawValue]
            let shown = min(max(resting - dragOffset, heights[0]), heights[2])
            VStack(alignment: .leading, spacing: 0) {
                header(heights: heights)
                    .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { headerHeight = $0 }
                if detent == .half {
                    grid
                } else {
                    strip
                        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { stripHeight = $0 }
                        .opacity(detent == .collapsed && dragOffset >= 0 ? 0 : 1)
                }
                Spacer(minLength: 0)
            }
            .frame(width: proxy.size.width, height: shown + bottom, alignment: .top)
            .background {
                UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28, style: .continuous)
                    .fill(ColorToken.surfaceSheet.color)
                    .shadow(color: Color(hex: 0x4B2938).opacity(0.12), radius: 10, y: -2)
            }
            .clipped()
            .frame(maxHeight: .infinity, alignment: .bottom)
            .offset(y: bottom)
            .onChange(of: heights[1] + bottom, initial: true) { cover = heights[1] + bottom }
        }
    }

    /// Title only, the strip, half the screen: visible heights above the screen's bottom safe area.
    private func heights(screen: CGFloat) -> [CGFloat] {
        let collapsed = headerHeight + 10
        let strip = headerHeight + stripHeight
        return [collapsed, strip, max(strip, screen / 2)]
    }

    private func header(heights: [CGFloat]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Capsule().fill(Color(hex: 0xCDBFB4)).frame(width: 36, height: 5)
                .frame(maxWidth: .infinity, minHeight: 21)
                .contentShape(Rectangle())
                .onTapGesture { settle(detent == .half ? .collapsed : Detent(rawValue: detent.rawValue + 1) ?? .half) }
                .accessibilityElement()
                .accessibilityLabel(Text("Recent places panel", bundle: .module, comment: "Map (P01): VoiceOver label of the panel's grabber"))
                .accessibilityValue(detentName)
                .accessibilityAdjustableAction { direction in
                    let step = direction == .increment ? 1 : -1
                    settle(Detent(rawValue: detent.rawValue + step) ?? detent)
                }
                .accessibilityIdentifier("map.panelGrabber")
            // Side by side as drawn; stacked when larger text doesn't leave room for both.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    title
                    Spacer()
                    allPlaces
                }
                VStack(alignment: .leading, spacing: 0) {
                    title
                    allPlaces
                }
            }
            .padding(.horizontal, 20)
        }
        .contentShape(Rectangle())
        .highPriorityGesture(drag(heights: heights))
    }

    private var detentName: Text {
        switch detent {
        case .collapsed: Text("Collapsed", bundle: .module, comment: "Map (P01): the places panel shows only its title")
        case .strip: Text("Recent places", bundle: .module)
        case .half: Text("Half screen", bundle: .module, comment: "Map (P01): the places panel fills half the screen")
        }
    }

    private func drag(heights: [CGFloat]) -> some Gesture {
        // Measured on the screen: the header moves with the finger, so its own space would see almost no movement.
        DragGesture(minimumDistance: 4, coordinateSpace: .global)
            .onChanged { dragOffset = $0.translation.height }
            .onEnded { value in
                let resting = heights[detent.rawValue]
                let target = resting - value.predictedEndTranslation.height
                let nearest = Detent.allCases.min { abs(heights[$0.rawValue] - target) < abs(heights[$1.rawValue] - target) } ?? detent
                settle(nearest)
            }
    }

    private func settle(_ target: Detent) {
        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.35)) {
            detent = target
            dragOffset = 0
        }
    }

    private var places: [(offset: Int, element: MapPlace)] {
        Array(model.recentPlaces.prefix(detent == .half ? 30 : 10).enumerated())
    }

    private var strip: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 19) {
                ForEach(places, id: \.element.id) { index, place in placeButton(place, index: index) }
            }
            .padding(.horizontal, 20)
            .padding(.top, 2)
        }
        .scrollIndicators(.hidden)
        .padding(.bottom, 14)
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: width), spacing: 19, alignment: .top)], alignment: .leading, spacing: 16) {
                ForEach(places, id: \.element.id) { index, place in placeButton(place, index: index) }
            }
            .padding(.horizontal, 20)
            .padding(.top, 2)
            .padding(.bottom, 14)
        }
        .scrollIndicators(.hidden)
    }

    private func placeButton(_ place: MapPlace, index: Int) -> some View {
        Button { select(place.id) } label: { recentPlace(place, index: index) }
            .buttonStyle(.plain)
            .accessibilityIdentifier("map.recentPlace")
    }

    private func recentPlace(_ place: MapPlace, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Color(hex: 0xC9B8AA)
                .overlay {
                    if let id = place.moments.first?.id, let image = model.images[id] { Image(uiImage: image).filling() }
                }
                .frame(width: width, height: 66)
                .clipShape(Self.photoShapes[index % Self.photoShapes.count])
                .task { if let id = place.moments.first?.id { await model.load(id) } }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                // One line as drawn; a long name or larger text wraps rather than being cut off.
                PlaceName(place: place).textStyle(.mapPlaceName).foregroundStyle(ColorToken.textPrimary.color)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Text(place.moments.count, format: .number).textStyle(.sectionCount).foregroundStyle(ColorToken.textSecondary.color)
            }
            .frame(width: width)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Map marker: \(PlaceName.text(place)) · \(Text("\(place.moments.count) moments", bundle: .module))", bundle: .module))
        .accessibilityAddTraits(.isButton)
    }

    private var title: some View {
        Text("Recent places", bundle: .module)
            .textStyle(.displaySection)
            .foregroundStyle(ColorToken.textPrimary.color)
            .accessibilityAddTraits(.isHeader)
    }

    private var allPlaces: some View {
        NavigationLink(value: MapRoute.places) {
            Text("All places", bundle: .module).textStyle(.ribbonAction).foregroundStyle(ColorToken.textLink.color)
                .frame(minHeight: Size.minimumTapTarget)
        }
        .accessibilityIdentifier("map.allPlaces")
    }
}

/// P06: `Map / Unavailable` - a drawn grid where the map would be, the card saying so and Try again - then PLACES.
struct MapUnavailableView: View {
    let model: MapModel
    let retry: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                MapUnavailableGrid()
                    .frame(height: 330)
                    .overlay(alignment: .top) {
                        HStack(spacing: 10) {
                            Icon.glyphInfo.image.resizable().frame(width: 20, height: 20).accessibilityHidden(true)
                            Text("The map can't be shown right now. Your places are all here.", bundle: .module)
                                .textStyle(.infoCard)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(ColorToken.textPrimary.color)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .frame(minHeight: 64)
                        .background(FieldBlob().fill(ColorToken.surfaceCard.color))
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                    }
                    .overlay(alignment: .bottomTrailing) {
                        Button(action: retry) {
                            Text("Try again", bundle: .module)
                                .textStyle(.control)
                                .foregroundStyle(ColorToken.textLink.color)
                                .frame(minHeight: Size.minimumTapTarget)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 20)
                        .padding(.bottom, 4)
                        .accessibilityIdentifier("map.retry")
                    }
                PlacesList(model: model)
                    .padding(.top, 20)
            }
            .padding(.bottom, 24)
        }
    }
}

/// The unavailable map's drawing: thin lines every 67 pt across and 55 pt down on a sand ground.
private struct MapUnavailableGrid: View {
    var body: some View {
        Canvas { context, size in
            var lines = Path()
            for x in stride(from: 67.0, to: size.width, by: 67) {
                lines.move(to: CGPoint(x: x, y: 0))
                lines.addLine(to: CGPoint(x: x, y: size.height))
            }
            for y in stride(from: 55.0, to: size.height, by: 55) {
                lines.move(to: CGPoint(x: 0, y: y))
                lines.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(lines, with: .color(Color(hex: 0xDDCFC1)), lineWidth: 1.5)
        }
        .background(Color(hex: 0xEADFD3))
        .accessibilityHidden(true)
    }
}

/// P05's `Card`: the location art, the title, why, Turn on location while it's off, and the way to add places.
struct NoPlacesCard: View {
    let locationIsUsable: Bool
    let unlocatedCount: Int
    let turnOnLocation: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ExplainerArt(glyph: .explainerPin)
            Text("No places yet", bundle: .module)
                .textStyle(.largeSheetTitle)
                .foregroundStyle(ColorToken.textPrimary.color)
                .multilineTextAlignment(.center)
                .padding(.top, 10)
                .accessibilityAddTraits(.isHeader)
            Group {
                if locationIsUsable {
                    Text("Moments show up here when they have a place. New moments get one when you save them.", bundle: .module)
                } else {
                    Text("Moments show up here when they have a place. Location is off, so new moments are saved without one.", bundle: .module)
                }
            }
            .textStyle(.sheetBody)
            .foregroundStyle(ColorToken.textBody.color)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 18)
            .padding(.top, 7)
            if !locationIsUsable {
                Button(action: turnOnLocation) { Text("Turn on location", bundle: .module) }
                    .buttonStyle(.primary)
                    .padding(.top, 16)
                    .accessibilityIdentifier("map.turnOnLocation")
            }
            if unlocatedCount > 0 {
                NavigationLink(value: MapRoute.unplaced) {
                    Text("Add places to \(unlocatedCount) moments", bundle: .module)
                        .textStyle(.control)
                        .foregroundStyle(ColorToken.textLink.color)
                        .frame(minHeight: Size.minimumTapTarget)
                }
                .padding(.top, 2)
                .accessibilityIdentifier("map.addPlaces")
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 2)
        .frame(maxWidth: .infinity)
        .background(DayCardBlob().fill(ColorToken.surfaceCard.color).shadow(color: Color(hex: 0x4B2938).opacity(0.1), radius: 10, y: 4))
    }
}

/// A place's name; one without a name says so.
struct PlaceName: View {
    let place: MapPlace
    var body: some View { Self.text(place) }

    static func text(_ place: MapPlace) -> Text {
        place.label.map { Text($0) } ?? Text("Unnamed place", bundle: .module)
    }

    /// "12 moments · Aug – Nov 2026".
    static func summary(_ place: MapPlace) -> Text {
        let count = Text("\(place.moments.count) moments", bundle: .module)
        let span = place.span
        let first = MemoriesView.dayDate(span.first)
        let last = MemoriesView.dayDate(span.last)
        let months = span.first / 100 == span.last / 100
            ? Text(first, format: Date.FormatStyle(timeZone: .gmt).month(.abbreviated).year())
            : Text(first..<last, format: Date.IntervalFormatStyle(timeZone: .gmt).month(.abbreviated).year())
        return Text("Map place summary: \(count) · \(months)", bundle: .module)
    }
}

/// P06's PLACES card, and the whole list from All places: pin, name, count, chevron.
struct PlacesList: View {
    let model: MapModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Places", bundle: .module)
                .textStyle(.labelCaps)
                .foregroundStyle(ColorToken.textSecondary.color)
                .accessibilityAddTraits(.isHeader)
                .padding(.horizontal, 22)
            VStack(spacing: 0) {
                ForEach(Array(model.places.enumerated()), id: \.element.id) { index, place in
                    NavigationLink(value: MapRoute.place(place.id)) {
                        HStack(spacing: 14) {
                            Icon.glyphPin.image
                                .resizable()
                                .frame(width: 20, height: 20)
                                .frame(width: 36, height: 36)
                                .background(Circle().fill(ColorToken.accentPeach.color))
                                .accessibilityHidden(true)
                            PlaceName(place: place).textStyle(.rowTitle)
                            Spacer(minLength: 8)
                            Text(place.moments.count, format: .number).textStyle(.rowValue).foregroundStyle(ColorToken.textTertiary.color)
                            Icon.glyphChevron.image
                                .resizable()
                                .frame(width: 20, height: 20)
                                .flipsForRightToLeftLayoutDirection(true)
                                .accessibilityHidden(true)
                        }
                        .foregroundStyle(ColorToken.textPrimary.color)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 64)
                        .overlay(alignment: .bottom) {
                            if index < model.places.count - 1 { ColorToken.separator.color.frame(height: 1).padding(.leading, 64) }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("map.place")
                }
            }
            .background(ColorToken.surfaceCard.color, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .padding(.horizontal, 16)
        }
    }
}

/// All places, as a list (also the way through the map without seeing it).
struct PlacesListView: View {
    let model: MapModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("All places", bundle: .module)
                    .textStyle(.displayHeadline)
                    .foregroundStyle(ColorToken.textPrimary.color)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
                PlacesList(model: model)
            }
            .padding(.bottom, 24)
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
        }
        .background(ColorToken.canvas.color.ignoresSafeArea())
        .navigationTitle(Text("All places", bundle: .module))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(removing: .title)
        .toolbarBackground(.hidden, for: .navigationBar)
    }
}

/// P02 on iPhone: the place's preview in a sheet as tall as it is.
struct PlacePreviewSheet: View {
    let model: MapModel
    let place: MapPlace
    let open: (MomentPager) -> Void
    let seeAll: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var height: CGFloat = 380

    var body: some View {
        ScrollView {
            PlacePreview(model: model, place: place, open: open, seeAll: seeAll, close: { dismiss() })
                .padding(.horizontal, 20)
                .padding(.top, 26)
                .padding(.bottom, 12)
                .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { height = $0 }
        }
        // The detent is the content's height; a scroll view lets larger text go past it rather than be cut.
        .scrollBounceBehavior(.basedOnSize)
        .presentationDetents([.height(height)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        .presentationBackground(ColorToken.surfaceSheet.color)
        .presentationBackgroundInteraction(.enabled(upThrough: .height(height)))
    }
}

/// P02: the place's name, its count and months, four of its moments and See all; in a sheet on iPhone, in the places
/// panel on iPad (X03).
struct PlacePreview: View {
    let model: MapModel
    let place: MapPlace
    let open: (MomentPager) -> Void
    let seeAll: () -> Void
    let close: () -> Void
    /// P02's four previews, each its own uneven outline.
    private static let previewShapes = [
        AnyShape(PlacePreviewBlobA()), AnyShape(PlacePreviewBlobB()), AnyShape(PlacePreviewBlobC()), AnyShape(PlacePreviewBlobD()),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                PlaceName(place: place)
                    .textStyle(.mapSheetTitle)
                    .foregroundStyle(ColorToken.textPrimary.color)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 12)
                Button(action: close) {
                    Icon.glyphClose.image
                        .resizable()
                        .frame(width: 20, height: 20)
                        .foregroundStyle(ColorToken.textPrimary.color)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(ColorToken.surfaceChip.color))
                        .frame(width: Size.minimumTapTarget, height: Size.minimumTapTarget)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Close", bundle: .module))
                .accessibilityIdentifier("place.close")
                .padding(.top, -8)
                .padding(.trailing, -6)
            }
            PlaceName.summary(place)
                .textStyle(.noteMeta)
                .foregroundStyle(ColorToken.textSecondary.color)
                .padding(.top, 4)
            HStack(spacing: 6) {
                ForEach(Array(place.moments.prefix(4).enumerated()), id: \.element.id) { index, moment in
                    Button { open(MomentPager(ids: place.moments.map(\.id), start: moment.id, origin: .place(place.label))) } label: { preview(moment, index: index) }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("place.preview")
                }
                ForEach(0..<max(0, 4 - place.moments.count), id: \.self) { _ in Color.clear.aspectRatio(86 / 108, contentMode: .fit) }
            }
            .padding(.top, 14)
            .padding(.horizontal, -3)
            Button(action: seeAll) {
                Text("See all \(place.moments.count) moments", bundle: .module)
            }
            .buttonStyle(.primary)
            .padding(.top, 20)
            .accessibilityIdentifier("place.seeAll")
        }
    }

    private func preview(_ moment: MapMoment, index: Int) -> some View {
        Color(hex: 0xC9B8AA)
            .overlay { if let image = model.images[moment.id] { Image(uiImage: image).filling() } }
            .aspectRatio(86 / 108, contentMode: .fit)
            .clipShape(Self.previewShapes[index])
            .overlay(alignment: .bottom) {
                if let duration = model.durations[moment.id] {
                    VideoBadge(duration: duration).padding(.bottom, 6)
                }
            }
            .environment(\.layoutDirection, .leftToRight)
            .task { await model.load(moment.id) }
            .accessibilityElement()
            .accessibilityLabel(moment.item.mediaType == .video ? Text("Video", bundle: .module) : Text("Photo", bundle: .module))
    }
}
