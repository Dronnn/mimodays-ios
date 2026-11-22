import Core
import DesignSystem
import Persistence
import SwiftData
import SwiftUI

/// Memories (M01, M01e): every moment by month and day, newest first. Each moment is grouped on the day it
/// was where it was taken (§H20), so a trip abroad keeps its own dates.
struct MemoriesView: View {
    @Bindable var model: MemoriesModel
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(AppRouter.self) private var router
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.calendar) private var calendar
    /// M13: the moments ticked while selecting; nil when not selecting.
    @State private var selection: Set<UUID>?
    /// E05 from M01e.
    @State private var importsPhotos = false
    /// M08/M09 here rather than on a screen of its own (Andrew, 2026-11-15).
    @State private var search: SearchModel
    @State private var isSearching: Bool
    @State private var showsFilters = false
    @FocusState private var isSearchFocused: Bool
    @Namespace private var searchSpace

    init(model: MemoriesModel, selection: Set<UUID>? = nil, search: SearchModel? = nil) {
        self.model = model
        _selection = State(initialValue: selection)
        _search = State(initialValue: search ?? SearchModel(library: model.library))
        _isSearching = State(initialValue: search != nil)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if selection == nil, !isSearching {
                    header
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                if isSearching { SearchResults(model: search) }
                // M01e keeps the switch and the search too (9.16).
                if model.isLoaded, selection == nil, !isSearching {
                    SegmentedControl(selection: $model.mode, options: [.timeline, .calendar]) { mode in
                        switch mode {
                        case .timeline: Text("Timeline", bundle: .module)
                        case .calendar: Text("Calendar", bundle: .module)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 21)
                    .accessibilityIdentifier("memories.mode")
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    if model.mode == .timeline, !model.isEmpty {
                        shortcuts
                            .padding(.top, 12)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                // The results take the list's place; until then the moments stay under the field.
                if !(isSearching && search.isSearching) {
                    if model.isEmpty, model.mode == .timeline {
                        emptyState
                            .padding(.top, 56)
                    } else {
                        moments
                    }
                }
            }
            .scrollTargetLayout()
            // On iPhone the buttons sit level with the status bar's bottom, as drawn.
            .statusBarLift(isSearching ? 0 : 9)
            .padding(.bottom, 24)
            .frame(maxWidth: 1180)
            .frame(maxWidth: .infinity)
        }
        .scrollPosition(id: $model.scrolledRow, anchor: .top)
        .scrollDismissesKeyboard(isSearching ? .immediately : .automatic)
        .background(ColorToken.canvas.color.ignoresSafeArea())
        // The title names the way back from a day; the bar itself stays hidden here.
        .navigationTitle(Text("Memories", bundle: .module))
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(selection == nil ? .automatic : .hidden, for: .tabBar)
        .safeAreaInset(edge: .top, spacing: 0) {
            Group {
                if selection != nil {
                    SelectBar(selection: $selection, all: model.allIDs)
                        .transition(.move(edge: .top).combined(with: .opacity))
                } else if isSearching {
                    searchBar
                }
            }
            .clearOfBareTopEdge()
        }
        .sheet(isPresented: $showsFilters) { SearchFiltersSheet(model: search) }
        // Into and out of selecting, however it's left (Cancel, a delete, the mode switch).
        .animation(.snappy, value: selection == nil)
        .memoriesSelectActions(model: model, selection: $selection)
        .photoImport(isPresented: $importsPhotos)
        .onChange(of: model.mode) { selection = nil }
        .memoriesDestinations(thisYear: model.today / 10_000)
        .navigationDestination(for: MemoriesTabRoute.self) { route in
            switch route {
            case .favorites: FavoritesView(model: model)
            }
        }
        .task { model.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in
            model.refresh()
            if isSearching { search.refresh() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.refresh() }
        }
    }

    /// The timeline or the calendar.
    @ViewBuilder
    private var moments: some View {
        switch model.mode {
        case .timeline:
            ForEach(Array(model.rows.enumerated()), id: \.element.id) { index, row in
                switch row {
                case let .month(key, count):
                    // M13 lists days only.
                    if selection == nil {
                        monthHeader(key, count: count, isFirst: index == 0)
                            .padding(.top, index == 0 ? 22 : 18)
                    }
                case let .day(key, items):
                    day(key, items)
                }
            }
        case .calendar:
            MemoriesCalendarView(model: model)
                .padding(.top, 12)
        }
    }

    // MARK: Search

    /// The field and Cancel, the chips under them; the list scrolls beneath.
    private var searchBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            SearchBar(query: $search.query, isFocused: $isSearchFocused, namespace: searchSpace, cancel: endSearch)
            SearchChips(model: search) {
                isSearchFocused = false
                showsFilters = true
            }
            .transition(.opacity.combined(with: .offset(y: -10)))
        }
        .padding(.bottom, 8)
        .background(ColorToken.canvas.color.ignoresSafeArea())
        .onAppear { isSearchFocused = true }
    }

    private func startSearch() {
        search.refresh()
        withAnimation(Self.searchMotion) { isSearching = true }
    }

    private func endSearch() {
        isSearchFocused = false
        withAnimation(Self.searchMotion) { isSearching = false }
        search.query = ""
        search.filters = SearchFilters()
    }

    private static let searchMotion = Animation.smooth(duration: 0.4)

    // MARK: Header

    /// Select (coral text), search and settings in ringed circles, then "Memories" with its brush underline and
    /// apricot star.
    private var header: some View {
        VStack(alignment: .leading, spacing: 7) {
            if selection == nil {
                HStack(spacing: 0) {
                    Spacer()
                    if model.isLoaded, !model.isEmpty, model.mode == .timeline {
                        SelectButton(selection: $selection, id: "memories.select")
                            .padding(.trailing, 14)
                    }
                    Button(action: startSearch) {
                        Icon.glyphSearch.image
                            .resizable()
                            .frame(width: 22, height: 22)
                            .matchedGeometryEffect(id: SearchMorph.glyph, in: searchSpace)
                            .foregroundStyle(ColorToken.textPrimary.color)
                            .frame(width: 40, height: 40)
                            .background {
                                Circle()
                                    .strokeBorder(ColorToken.textPrimary.color, lineWidth: 1.3)
                                    .matchedGeometryEffect(id: SearchMorph.shape, in: searchSpace)
                            }
                            .frame(width: Size.minimumTapTarget, height: Size.minimumTapTarget)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Search", bundle: .module))
                    .accessibilityIdentifier("memories.search")
                    Button { router.open(.settings) } label: {
                        Icon.glyphGear.image
                            .resizable()
                            .frame(width: 22, height: 22)
                            .foregroundStyle(ColorToken.textPrimary.color)
                            .frame(width: 40, height: 40)
                            .overlay(Circle().strokeBorder(ColorToken.textPrimary.color, lineWidth: 1.3))
                            .frame(width: Size.minimumTapTarget, height: Size.minimumTapTarget)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Settings", bundle: .module))
                    .accessibilityIdentifier("settings")
                }
                .padding(.trailing, 19)
                        }
            Text("Memories", bundle: .module)
                .textStyle(.screenTitle)
                .foregroundStyle(ColorToken.textPrimary.color)
                .fixedSize(horizontal: false, vertical: true)
                .overlay(alignment: .bottomLeading) {
                    Icon.markBrush.image
                        .resizable()
                        .frame(width: 160, height: 10.5)
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
                .padding(.leading, 23)
                .accessibilityAddTraits(.isHeader)
        }
    }

    /// Chips under the switch: Favorites, Collections, On this day.
    private var shortcuts: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                NavigationLink(value: MemoriesTabRoute.favorites) {
                    chip(.glyphHeart, Text("Favorites", bundle: .module))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("memories.favorites")
                NavigationLink(value: MemoriesRoute.collections) {
                    chip(.glyphCollectionsChip, Text("Collections", bundle: .module))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("memories.collections")
                NavigationLink(value: MemoriesRoute.onThisDay) {
                    // `Chip / On this day`: the apricot star mark, not a glyph.
                    chip(.markStarSmall, Text("On this day", bundle: .module), size: CGSize(width: 16, height: 16.5), tint: ColorToken.accentApricot.color)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("memories.onThisDay")
            }
            .padding(.horizontal, 20)
        }
        .scrollIndicators(.hidden)
    }

    private func chip(_ icon: Icon, _ title: Text, size: CGSize = CGSize(width: 15, height: 15), tint: Color? = nil) -> some View {
        HStack(spacing: 6) {
            icon.image
                .resizable()
                .frame(width: size.width, height: size.height)
                .foregroundStyle(tint ?? ColorToken.textPrimary.color)
                .accessibilityHidden(true)
            title
                .textStyle(.reviewChip)
        }
        .foregroundStyle(ColorToken.textPrimary.color)
        .padding(.horizontal, 13)
        .frame(minHeight: 34)
        .background(ReviewChipBlob().fill(ColorToken.surfaceChip.color))
        .frame(minHeight: Size.minimumTapTarget)
        .contentShape(Rectangle())
    }

    // MARK: Months and days

    private func monthHeader(_ key: Int, count: Int, isFirst: Bool) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(Self.monthDate(key), format: Date.FormatStyle(timeZone: .gmt).month(.wide).year())
                .textStyle(.displaySection)
                .foregroundStyle(ColorToken.textPrimary.color)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            Text("\(count) moments", bundle: .module)
                .textStyle(.sectionCount)
                .foregroundStyle(ColorToken.textSecondary.color)
        }
        .padding(.leading, 23)
        .padding(.trailing, 20)
        .overlay(alignment: .topLeading) {
            if isFirst {
                Icon.markTicksB.image
                    .resizable()
                    .frame(width: 22.5, height: 16.7)
                    .foregroundStyle(ColorToken.accentCoralMark.color)
                    .offset(x: 8, y: -10)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func day(_ key: Int, _ items: [MemoryItem]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            dayLabel(key)
                .textStyle(.labelCaps)
                .foregroundStyle(ColorToken.textSecondary.color)
                .padding(.leading, 22)
                .accessibilityAddTraits(.isHeader)
            // X02: iPad's tiles are about 136 pt, six to a row; iPhone fits three to a row.
            LazyVGrid(columns: [GridItem(.adaptive(minimum: sizeClass == .regular ? 132 : 100), spacing: 4)], spacing: 4) {
                ForEach(items) { item in
                    Group {
                        if selection != nil {
                            SelectableTile(selection: $selection, id: item.id, shape: StripTile.shape(item.capturedAt)) {
                                MemoryTile(item: item, detail: model.details[item.id], image: model.images[item.id], leavesRoomForMark: true)
                            }
                        } else {
                            MomentTileLink(MemoriesRoute.moment(MomentPager(ids: model.allIDs, start: item.id))) {
                                MemoryTile(item: item, detail: model.details[item.id], image: model.images[item.id])
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .task { await model.load(item.id) }
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.top, 9)
        .padding(.bottom, 5)
    }

    /// "TODAY · WED, NOV 11", "YESTERDAY · TUE, NOV 10", "MON, NOV 9"; years only when it isn't this one.
    private func dayLabel(_ key: Int) -> Text { Self.dayLabel(key, now: model.now, calendar: calendar) }

    /// Also P3.5's Choose videos.
    static func dayLabel(_ key: Int, now: Date, calendar: Calendar) -> Text {
        let date = dayDate(key)
        let today = LocalDay(now, in: calendar.timeZone).key
        var format = Date.FormatStyle(timeZone: .gmt).weekday(.abbreviated).month(.abbreviated).day()
        if key / 10_000 != today / 10_000 { format = format.year() }
        let text = Text(date, format: format)
        if key == today { return Text("Day label today: \(text)", bundle: .module) }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           key == LocalDay(yesterday, in: calendar.timeZone).key {
            return Text("Day label yesterday: \(text)", bundle: .module)
        }
        return text
    }

    /// Noon UTC on that day: formatted in UTC it stays the same day whatever the device's zone.
    static func dayDate(_ key: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar.date(from: DateComponents(year: key / 10_000, month: key / 100 % 100, day: key % 100, hour: 12)) ?? .distantPast
    }

    static func monthDate(_ key: Int) -> Date { dayDate(key * 100 + 1) }

    // MARK: Empty

    /// M01e: what will be here, and the ways to start.
    private var emptyState: some View {
        VStack(spacing: 0) {
            ExplainerArt(glyph: .tabMemories)
            Text("No memories yet", bundle: .module)
                .textStyle(.emptyTitle)
                .foregroundStyle(ColorToken.textPrimary.color)
                .padding(.top, 16)
                .accessibilityAddTraits(.isHeader)
            Text("Moments you capture on Today show up here, grouped by day.", bundle: .module)
                .textStyle(.body)
                .foregroundStyle(ColorToken.textBody.color)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
                .padding(.horizontal, 34)
            Button { router.open(.capture(promptID: nil)) } label: {
                Text("Catch a moment", bundle: .module)
            }
            .buttonStyle(.primary)
            .padding(.horizontal, 20)
            .padding(.top, 21)
            .accessibilityIdentifier("memories.capture")
            Button { importsPhotos = true } label: { Text("Import from Photos", bundle: .module) }
                .buttonStyle(.text)
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .accessibilityIdentifier("memories.import")
        }
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity)
    }
}

/// M13: an empty circle on each tile; a ticked one gets a coral check and a coral border.
struct SelectionMark: View {
    let isOn: Bool
    /// The tile's own hand-cut shape: the ring follows its edge.
    let shape: AnyShape

    var body: some View {
        // Twice as wide and clipped to the shape: 3 pt inside the tile's edge, wherever it bends.
        shape
            .stroke(isOn ? ColorToken.actionCoral.color : .clear, lineWidth: 6)
            .clipShape(shape)
            .overlay(alignment: .bottomTrailing) {
                ZStack {
                    Circle().fill(isOn ? ColorToken.actionCoral.color : ColorToken.mediaScrim.color)
                    Circle().strokeBorder(ColorToken.mediaFrame.color, lineWidth: 2)
                    if isOn { Icon.glyphCheck.image.resizable().frame(width: 16, height: 16).foregroundStyle(ColorToken.mediaFrame.color) }
                }
                .frame(width: 26, height: 26)
                .padding(7)
            }
            .environment(\.layoutDirection, .leftToRight)
            .accessibilityHidden(true)
    }
}

/// `Badge / Voice`: a mic on a dark disc, offset like the favourite's heart - tiles and Day cards.
struct VoiceBadge: View {
    var body: some View {
        // The asset has room around the mic: drawn 27.3 pt so the mic itself is 14 x 20, as designed.
        Icon.glyphMic.image
            .resizable()
            .frame(width: 27.3, height: 27.3)
            .frame(width: 14, height: 20)
            .foregroundStyle(.white)
            .offset(x: MemoryTile.badgeOffset, y: MemoryTile.badgeOffset)
            .frame(width: 26, height: 26)
            .background(Circle().fill(ColorToken.mediaScrim.color))
            .accessibilityHidden(true)
    }
}

/// `Badge / Video`: a play triangle and the length on a dark capsule - tiles and Day cards.
struct VideoBadge: View {
    let duration: Double

    var body: some View {
        HStack(spacing: 3) {
            // The asset has room around the triangle: drawn 14.7 pt so the triangle itself is 7.2 x 8.8.
            Icon.glyphPlay.image
                .resizable()
                .frame(width: 14.7, height: 14.7)
                .offset(x: -1.2)
                .frame(width: 9, height: 10)
            Text(Duration.seconds(duration.rounded()), format: .time(pattern: .minuteSecond))
                .textStyle(.tileBadge)
        }
        .foregroundStyle(.white)
        .padding(.leading, 9)
        .padding(.trailing, 8)
        .frame(height: 22)
        .background(Capsule().fill(ColorToken.mediaScrim.color))
    }
}

/// `Moment / Tile`: the composed thumbnail in one of the strip's hand-cut shapes, its selfie window included, with a heart for a favourite,
/// a mic for a voice note and the length of a video.
struct MemoryTile: View {
    let item: MemoryItem
    let detail: TileDetail?
    let image: UIImage?
    /// Select mode: the mic steps left of the selection circle (M13).
    var leavesRoomForMark = false
    /// F05's small tiles: the video's length goes top left, clear of the selection circle (the mic steps aside too);
    /// they don't show the favourite heart, which lives there.
    var videoBadgeAtTop = false
    /// The tile badges' deliberate offset of their glyph from the disc's centre (design: 5 pt right and down).
    static let badgeOffset: CGFloat = 5

    var body: some View {
        Color(hex: 0xC9B8AA)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if item.mediaType == .text {
                    PaperTileFace(excerpt: detail?.excerpt)
                } else if let image {
                    Image(uiImage: image).filling()
                }
            }
            .tileMotion(item.id, isVideo: item.mediaType == .video, still: image)
            .clipShape(StripTile.shape(item.capturedAt))
            .background(StripTile.shadow(StripTile.shape(item.capturedAt)))
            .overlay(alignment: .topLeading) {
                if item.isFavorite, !videoBadgeAtTop {
                    // `Badge / Favorite`: the heart sits 5 pt right of and below the disc's centre, past its
                    // edge - on purpose, never centred (Andrew, 2026-11-14).
                    HeartShape()
                        .fill(ColorToken.actionCoral.color)
                        .frame(width: 20, height: 18)
                        .offset(x: Self.badgeOffset, y: Self.badgeOffset)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(ColorToken.mediaFrame.color))
                        .padding(7)
                }
            }
            .overlay(alignment: videoBadgeAtTop ? .topLeading : .bottomLeading) {
                if let duration = detail?.duration {
                    VideoBadge(duration: duration)
                        .padding(videoBadgeAtTop ? 6 : 7)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if detail?.hasVoiceNote == true {
                    VoiceBadge()
                        .padding(7)
                        .padding(.trailing, leavesRoomForMark || videoBadgeAtTop ? 29 : 0)
                }
            }
            .environment(\.layoutDirection, .leftToRight)
            .accessibilityElement()
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isImage)
            .accessibilityIdentifier("memories.tile")
    }

    /// The first word of a tile's VoiceOver description.
    static func kind(_ type: MediaType) -> Text {
        switch type {
        case .video: Text("Video", bundle: .module)
        case .text: Text("Written moment", bundle: .module)
        default: Text("Photo", bundle: .module)
        }
    }

    /// "Video, 6:42 PM, surprise, favorite, voice note".
    private var label: Text {
        var clock = Date.FormatStyle(date: .omitted, time: .shortened)
        clock.timeZone = item.captured.timeZone
        var text = MemoryTile.kind(item.mediaType)
        text = text + Text(verbatim: ", ") + Text(item.capturedAt, format: clock)
        // P8.11: the words are read too.
        if let excerpt = detail?.excerpt { text = text + Text(verbatim: ", ") + Text(excerpt) }
        if item.origin == .randomPrompt { text = text + Text(verbatim: ", ") + Text("surprise", bundle: .module) }
        if item.isFavorite { text = text + Text(verbatim: ", ") + Text("Description is favorite", bundle: .module) }
        if detail?.hasVoiceNote == true { text = text + Text(verbatim: ", ") + Text("Description has voice note", bundle: .module) }
        return text
    }
}
