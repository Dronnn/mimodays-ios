@preconcurrency import AVFoundation
import Core
import DesignSystem
import Persistence
import SwiftData
import SwiftUI

/// Keeps the viewer's model while it's on screen; any screen can open it from a `MomentPager`.
struct MomentViewerScreen: View {
    let pager: MomentPager
    @Environment(\.mediaLibrary) private var library
    @Environment(\.mosaicZoom) private var mosaicZoom

    var body: some View {
        if let library {
            if pager.origin == .mosaic, let mosaicZoom {
                // U40: the piece grows into the card, the Mosaic dimming behind; closing shrinks it back.
                MomentViewerHost(model: MomentViewerModel(pager: pager, library: library))
                    .navigationTransition(.zoom(sourceID: pager.start, in: mosaicZoom))
            } else {
                MomentViewerHost(model: MomentViewerModel(pager: pager, library: library))
            }
        }
    }
}

extension EnvironmentValues {
    /// The Mosaic's pieces, which a Memory Card opened from them grows out of (U40).
    @Entry var mosaicZoom: Namespace.ID?
}

private struct MomentViewerHost: View {
    @State var model: MomentViewerModel

    var body: some View {
        MomentViewer(model: model)
    }
}

/// The Memory Card everywhere a single moment opens (U20-U25, U42): one card per page on the cream canvas,
/// swiping sideways to the others it was opened among, the neighbours peeking at the edges.
struct MomentViewer: View {
    @Bindable var model: MomentViewerModel
    @Environment(\.camera) private var camera
    @Environment(MoviePreferences.self) private var moviePreferences: MoviePreferences?
    /// M07 while it is open.
    @State private var editing: EditMomentModel?
    /// M15 while it is open, for this moment.
    @State private var deleting: ViewerMoment?
    /// The ••• menu's Add to collection, for this moment.
    @State private var collecting: CollectingMoment?
    /// E01, from Share.
    @State private var exporting: MomentExportModel?
    /// The status bar's height and the screen's width: the selfie window is laid out from them, as on the camera.
    @State private var screenWidth: CGFloat = 0
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        GeometryReader { proxy in
            let slot = MemoryCardGeometry.slotWidth(screen: proxy.size.width)
            ScrollView(.horizontal) {
                LazyHStack(spacing: MemoryCardGeometry.pageGap) {
                    ForEach(model.ids, id: \.self) { id in
                        page(id)
                            .frame(width: slot, height: proxy.size.height)
                            .task { await model.load(id) }
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, (proxy.size.width - slot) / 2, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned(limitBehavior: .alwaysByOne))
            .scrollPosition(id: $model.current)
            .scrollIndicators(.hidden)
        }
        .background(ColorToken.canvas.color.ignoresSafeArea())
        // M05/M06 draw their own bar: back with the day, the time, •••. Swiping back still works.
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .background(SwipeBackEnabler())
        .safeAreaInset(edge: .top, spacing: 0) { topBar }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let moment = model.currentMoment {
                VStack(spacing: 0) {
                    position
                    actions(moment)
                }
            }
        }
        .fullScreenCover(item: $editing) { edit in
            EditMomentView(model: edit) { model.removeFromPager(edit.id) }
        }
        .sheet(item: $deleting) { moment in
            DeleteConfirmationSheet(count: 1, mediaType: moment.mediaType, movieDrafts: model.movieDrafts(moment.id)) {
                model.delete(moment.id)
            }
        }
        .sheet(item: $collecting) { collecting in
            CollectionPickerSheet(library: model.library, selection: Binding(
                get: { collecting.selection },
                set: { self.collecting?.selection = $0 }
            ))
            .onDisappear { model.setCollections(self.collecting?.selection ?? collecting.selection, for: collecting.id) }
        }
        .sheet(item: $exporting) { MomentExportSheet(model: $0) }
        .onChange(of: model.ids.isEmpty) { _, isEmpty in if isEmpty { dismiss() } }
        .onChange(of: model.current) { model.stopVoice() }
        .onDisappear { model.stopVoice() }
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in
            Task { await model.reload() }
        }
        // Outside the bars' insets: the screen's own.
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { screenWidth = $0 }
    }

    @ViewBuilder
    private func page(_ id: UUID) -> some View {
        if let moment = model.moments[id] {
            MemoryCardPage(
                model: model, moment: moment, isCurrent: model.current == id, screenWidth: screenWidth,
                edit: { edit(id) }, step: { model.step($0) }
            )
        } else {
            Color.clear
        }
    }

    // MARK: Bar

    /// Back to where the card was opened from (U42).
    private func backLabel(_ moment: ViewerMoment) -> Text {
        switch model.origin {
        case .day: Self.day(moment.captured)
        case .today: Text("Today", bundle: .module)
        case .mosaic: Text("Mosaic", bundle: .module)
        case .onThisDay: Text("On this day", bundle: .module)
        case .favorites: Text("Favorites", bundle: .module)
        case .search: Text("Search", bundle: .module)
        case let .collection(title): Text(title)
        case .place: Text("Map", bundle: .module)
        }
    }

    /// From the Map: which of the place's moments this is (U41).
    @ViewBuilder
    private var position: some View {
        if case let .place(name) = model.origin, model.ids.count > 1,
           let index = model.current.flatMap({ model.ids.firstIndex(of: $0) }) {
            Group {
                if let name {
                    Text("\(index + 1) of \(model.ids.count) at \(name)", bundle: .module)
                } else {
                    Text("\(index + 1) of \(model.ids.count)", bundle: .module)
                }
            }
            .textStyle(.noteMeta)
            .foregroundStyle(ColorToken.textSecondary.color)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .accessibilityIdentifier("viewer.position")
        }
    }

    /// `Navigation / Back bar`: ‹ and where it was opened from ("Nov 11", "Map"), its time, the ••• menu.
    private var topBar: some View {
        let ink = ColorToken.textPrimary.color
        return ZStack {
            if let moment = model.currentMoment {
                Self.time(moment.captured, date: false)
                    .textStyle(.editorTitle)
                    .foregroundStyle(ink)
                    .accessibilityAddTraits(.isHeader)
            }
            HStack(spacing: 0) {
                Button { dismiss() } label: {
                    HStack(spacing: 0) {
                        Icon.glyphBack.image
                            .resizable()
                            .frame(width: 24, height: 24)
                            .foregroundStyle(ink)
                            .flipsForRightToLeftLayoutDirection(true)
                        if let moment = model.currentMoment {
                            backLabel(moment)
                                .textStyle(.editorCancel)
                                .foregroundStyle(ColorToken.textLink.color)
                                .lineLimit(1)
                        }
                    }
                    .frame(minHeight: Size.minimumTapTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Back", bundle: .module))
                .accessibilityIdentifier("viewer.back")
                Spacer(minLength: 8)
                if let moment = model.currentMoment {
                    Menu {
                        Button { collecting = CollectingMoment(id: moment.id, selection: Set(moment.collections.map(\.id))) } label: {
                            Label { Text("Add to collection", bundle: .module) } icon: { Icon.glyphCollection.image }
                        }
                        NavigationLink(value: MemoriesRoute.day(LocalDay(moment.captured.instant, in: moment.captured.timeZone).key)) {
                            Label { Text("Show the whole day", bundle: .module) } icon: { Icon.glyphClock.image }
                        }
                        if moment.selfiePath != nil, moment.format != .square,
                           let layout = moment.video?.layout ?? moment.photo?.layout {
                            Picker(selection: Binding(
                                get: { layout.isHalves ? PiPLayout.Arrangement.halves : .window },
                                set: { model.setArrangement($0, for: moment.id) }
                            )) {
                                ForEach(PiPLayout.Arrangement.allCases, id: \.self) { $0.label }
                            } label: {
                                Text("Layout", bundle: .module, comment: "Camera and viewer ••• menus (H.8): the selfie in its window, or both cameras in halves")
                            }
                            .pickerStyle(.menu)
                            .accessibilityIdentifier("viewer.arrangement")
                        }
                    } label: {
                        Icon.glyphMore.image
                            .resizable()
                            .frame(width: 24, height: 24)
                            .foregroundStyle(ink)
                            .frame(width: Size.minimumTapTarget, height: Size.minimumTapTarget)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel(Text("More", bundle: .module))
                    .accessibilityIdentifier("viewer.more")
                }
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 4)
        .frame(height: 44)
    }

    // MARK: Actions

    /// Share, favourite, edit and delete.
    private func actions(_ moment: ViewerMoment) -> some View {
        let tint = ColorToken.textPrimary.color
        return HStack {
            // E01: as seen or as the camera's files, with what the moment has.
            Button { exporting = MomentExportModel(ids: [moment.id], library: model.library, exactPlace: moviePreferences?.value.exactPlaceInFiles ?? false) } label: {
                Icon.glyphShare.image.resizable().frame(width: 24, height: 24).foregroundStyle(tint)
                    .frame(width: Size.minimumTapTarget, height: Size.minimumTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Share", bundle: .module))
            .accessibilityIdentifier("viewer.share")
            .frame(maxWidth: .infinity)
            Button { model.toggleFavorite(moment.id) } label: {
                (moment.isFavorite ? Icon.glyphHeartFilled : .glyphHeart).image
                    .resizable()
                    .frame(width: 24, height: 24)
                    .foregroundStyle(moment.isFavorite ? ColorToken.actionCoral.color : tint)
                    .frame(width: Size.minimumTapTarget, height: Size.minimumTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.selection, trigger: moment.isFavorite)
            .accessibilityLabel(Text("Favorite", bundle: .module))
            .accessibilityAddTraits(moment.isFavorite ? .isSelected : [])
            .accessibilityIdentifier("viewer.favorite")
            .frame(maxWidth: .infinity)
            Button { edit(moment.id) } label: {
                Icon.glyphNote.image
                    .resizable()
                    .frame(width: 24, height: 24)
                    .foregroundStyle(tint)
                    .frame(width: Size.minimumTapTarget, height: Size.minimumTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Edit", bundle: .module))
            .accessibilityIdentifier("viewer.edit")
            .frame(maxWidth: .infinity)
            Button {
                model.stopVoice()
                deleting = moment
            } label: {
                Icon.glyphTrash.image
                    .resizable()
                    .frame(width: 24, height: 24)
                    .foregroundStyle(tint)
                    .frame(width: Size.minimumTapTarget, height: Size.minimumTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Delete", bundle: .module))
            .accessibilityIdentifier("viewer.delete")
            .frame(maxWidth: .infinity)
        }
        .padding(.top, 6)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity)
        .background {
            ColorToken.canvas.color
                .overlay(alignment: .top) {
                    Rectangle().fill(ColorToken.textPrimary.color.opacity(0.14)).frame(height: 0.6)
                }
                .ignoresSafeArea()
        }
    }

    private func edit(_ id: UUID) {
        model.stopVoice()
        let services = camera ?? .simulated
        editing = EditMomentModel(id: id, library: model.library, voice: services.voice, places: services.places)
    }

    // MARK: Pieces

    /// "Nov 11", in the moment's own time zone.
    static func day(_ captured: CaptureTime) -> Text {
        var format = Date.FormatStyle().month(.abbreviated).day()
        format.timeZone = captured.timeZone
        return Text(captured.instant, format: format)
    }

    /// "6:42 PM", or "Wed, Nov 11, 2026 · 6:42 PM", in the moment's own time zone.
    static func time(_ captured: CaptureTime, date: Bool) -> Text {
        var clock = Date.FormatStyle(date: .omitted, time: .shortened)
        clock.timeZone = captured.timeZone
        guard date else { return Text(captured.instant, format: clock) }
        var day = Date.FormatStyle().weekday(.abbreviated).month(.abbreviated).day().year()
        day.timeZone = captured.timeZone
        return Text("Day and time: \(Text(captured.instant, format: day)) · \(Text(captured.instant, format: clock))", bundle: .module)
    }
}

/// `Viewer / Voice pill`: play or stop, its length and its waveform, filling coral as it plays.
/// On the canvas a cream hand-cut card; on a video a translucent cream capsule without the waveform.
struct VoicePill: View {
    let model: MomentViewerModel
    let id: UUID
    let voice: ViewerMoment.Voice
    let onPhoto: Bool

    var body: some View {
        let isPlaying = model.playingVoice == id
        let progress = isPlaying && voice.duration > 0 ? min(model.voiceTime / voice.duration, 1) : 0
        let length = Text(Duration.seconds(voice.duration.rounded()), format: .time(pattern: .minuteSecond))
        Button { model.toggleVoice(id) } label: {
            Group {
                if onPhoto {
                    HStack(spacing: 8) {
                        (isPlaying ? Icon.glyphPause : .glyphPlay).image.resizable().scaledToFit().frame(width: 20, height: 20)
                        Text("Voice note · \(length)", bundle: .module).textStyle(.voicePill)
                    }
                    .foregroundStyle(ColorToken.mediaFrame.color)
                    .padding(.leading, 12)
                    .padding(.trailing, 20)
                    .frame(minWidth: 230, minHeight: 40, alignment: .leading)
                    .background(Capsule().fill(ColorToken.mediaFrame.color.opacity(0.18)))
                } else {
                    HStack(spacing: 12) {
                        (isPlaying ? Icon.glyphPause : .glyphPlay).image
                            .resizable()
                            .scaledToFit()
                            .frame(width: 20, height: 20)
                            .foregroundStyle(ColorToken.textOnCoral.color)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(ColorToken.actionCoral.color))
                        Text("Voice note · \(length)", bundle: .module)
                            .textStyle(.voicePill)
                            .foregroundStyle(ColorToken.textPrimary.color)
                        Spacer(minLength: 8)
                        WaveformBars(
                            levels: model.voiceLevels[id] ?? [], count: MomentViewerModel.voiceBars,
                            filled: Int((progress * Double(MomentViewerModel.voiceBars)).rounded()),
                            minHeight: 8, maxHeight: 22, rest: ColorToken.textPrimary.color.opacity(0.55)
                        )
                        .frame(width: CGFloat(MomentViewerModel.voiceBars) * 6, height: 24)
                        .environment(\.layoutDirection, .leftToRight)
                        .accessibilityHidden(true)
                    }
                    .padding(.leading, 10)
                    .padding(.trailing, 26)
                    .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                    .background(FieldBlob().fill(ColorToken.surfaceCard.color).shadow(color: Color(hex: 0x4B2938).opacity(0.08), radius: 2, y: 1))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Voice note · \(length)", bundle: .module))
        .accessibilityValue(isPlaying ? Text(Duration.seconds(model.voiceTime.rounded()), format: .time(pattern: .minuteSecond)) : Text(verbatim: ""))
        .accessibilityHint(Text(isPlaying ? "Stops it" : "Plays it", bundle: .module))
        .accessibilityIdentifier("viewer.voice")
    }
}

/// The ••• menu's Add to collection: the moment and the collections ticked so far.
struct CollectingMoment: Identifiable {
    let id: UUID
    var selection: Set<UUID>
}

/// The system share sheet for files.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context _: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_: UIActivityViewController, context _: Context) {}
}

/// Keeps the edge swipe back on screens that hide the navigation bar to draw their own (M05/M06).
struct SwipeBackEnabler: UIViewControllerRepresentable {
    func makeUIViewController(context _: Context) -> Controller { Controller() }
    func updateUIViewController(_: Controller, context _: Context) {}

    final class Controller: UIViewController {
        private weak var previous: (any UIGestureRecognizerDelegate)?
        private weak var navigation: UINavigationController?

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            guard let navigation = navigationController, navigation.viewControllers.count > 1,
                  let gesture = navigation.interactivePopGestureRecognizer else { return }
            self.navigation = navigation
            previous = gesture.delegate
            gesture.isEnabled = true
            gesture.delegate = nil
        }

        // Back as it was before the screen goes: a nil delegate on the root screen can freeze the swipe.
        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            navigation?.interactivePopGestureRecognizer?.delegate = previous
        }
    }
}
