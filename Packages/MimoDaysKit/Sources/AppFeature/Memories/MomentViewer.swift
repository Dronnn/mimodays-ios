@preconcurrency import AVFoundation
import Core
import DesignSystem
import SwiftData
import SwiftUI

/// Keeps the viewer's model while it's on screen; any screen can open it from a `MomentPager`.
struct MomentViewerScreen: View {
    let pager: MomentPager
    @Environment(\.mediaLibrary) private var library

    var body: some View {
        if let library {
            MomentViewerHost(model: MomentViewerModel(pager: pager, library: library))
        }
    }
}

private struct MomentViewerHost: View {
    @State var model: MomentViewerModel

    var body: some View {
        MomentViewer(model: model)
    }
}

/// M05 (photo) and M06 (video): one moment per page, swiping sideways to the others it was opened among.
/// A photo sits on the cream canvas; a video fills the screen, with cream controls.
struct MomentViewer: View {
    @Bindable var model: MomentViewerModel
    @Environment(\.camera) private var camera
    /// M07 while it is open.
    @State private var editing: EditMomentModel?
    /// M15 while it is open, for this moment.
    @State private var deleting: ViewerMoment?
    /// The ••• menu's Add to collection, for this moment.
    @State private var collecting: CollectingMoment?
    /// A video's composed file, ready to share.
    @State private var sharing: SharedFile?
    @State private var preparingShare = false
    /// The status bar's height: the video's selfie window is laid out from it, as on the camera.
    @State private var screenTop: CGFloat = 0
    @State private var screenWidth: CGFloat = 0
    @Environment(\.dismiss) private var dismiss

    private var isVideo: Bool { model.currentMoment?.mediaType == .video }

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(model.ids, id: \.self) { id in
                    page(id)
                        .containerRelativeFrame([.horizontal, .vertical])
                        .task { await model.load(id) }
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $model.current)
        .scrollIndicators(.hidden)
        .background((isVideo ? Color.black : ColorToken.canvas.color).ignoresSafeArea())
        // M05/M06 draw their own bar: back with the day, the time, •••. Swiping back still works.
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .background(SwipeBackEnabler())
        .safeAreaInset(edge: .top, spacing: 0) { topBar }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let moment = model.currentMoment { actions(moment) }
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
        .sheet(item: $sharing) { ShareSheet(items: [$0.url]) }
        .onChange(of: model.ids.isEmpty) { _, isEmpty in if isEmpty { dismiss() } }
        .onChange(of: model.current) { model.stopVoice() }
        .onDisappear { model.stopVoice() }
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in
            Task { await model.reload() }
        }
        // Outside the bars' insets: the screen's own.
        .onGeometryChange(for: CGFloat.self, of: { $0.safeAreaInsets.top }) { screenTop = $0 }
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { screenWidth = $0 }
    }

    @ViewBuilder
    private func page(_ id: UUID) -> some View {
        if let moment = model.moments[id] {
            if moment.mediaType == .video {
                VideoPage(model: model, moment: moment, isCurrent: model.current == id, topInset: screenTop)
            } else {
                photoPage(moment)
            }
        } else {
            Color.clear
        }
    }

    // MARK: Bar

    /// `Navigation / Back bar`: ‹ and the moment's day ("Nov 11"), its time, the ••• menu. Cream on a video.
    private var topBar: some View {
        let ink = (isVideo ? ColorToken.mediaFrame : .textPrimary).color
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
                            Self.day(moment.captured)
                                .textStyle(.editorCancel)
                                .foregroundStyle((isVideo ? ColorToken.mediaFrame : .textLink).color)
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

    // MARK: Photo (M05)

    private func photoPage(_ moment: ViewerMoment) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Color(hex: 0x9C8573)
                    .overlay {
                        if let image = model.image(moment.mainPath) { Image(uiImage: image).filling() }
                    }
                    // The whole photo, as taken and as shared (9.28), with its window where it was taken.
                    .aspectRatio(moment.photo?.aspectRatio ?? 386 / 440, contentMode: .fit)
                    .clipShape(ViewerPhotoBlob())
                    .overlay {
                        if let layout = moment.photo?.layout, screenWidth > 0 {
                            GeometryReader { proxy in
                                ViewerSelfieWindow(
                                    model: model, momentID: moment.id, saved: layout, screenWidth: screenWidth, topInset: screenTop, shown: proxy.size
                                ) {
                                    if let image = model.image(moment.selfiePath) {
                                        Image(uiImage: image).filling()
                                    }
                                }
                            }
                        }
                    }
                    .environment(\.layoutDirection, .leftToRight)
                    .accessibilityElement()
                    .accessibilityLabel(Text(moment.selfiePath == nil ? "Photo" : "Photo with selfie", bundle: .module))
                    .accessibilityAddTraits(.isImage)
                    .padding(.horizontal, 8)
                    .padding(.top, 8)
                meta(moment)
                    .padding(.horizontal, 14)
                    .padding(.top, 14)
                MomentWords(moment: moment, onPhoto: false)
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                if let voice = moment.voice {
                    VoicePill(model: model, id: moment.id, voice: voice, onPhoto: false)
                        .padding(.horizontal, 16)
                        .padding(.top, 14)
                }
                if !moment.collections.isEmpty {
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(moment.collections) { collection in
                                NavigationLink(value: MemoriesRoute.collection(collection.id)) {
                                    SearchChip(icon: .glyphCollection, title: Text(collection.title), isOn: false, id: "") {}
                                        .allowsHitTesting(false)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("viewer.collection")
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    .scrollIndicators(.hidden)
                    .padding(.top, 10)
                }
            }
            .padding(.bottom, 20)
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
        }
    }

    /// The place on the left, where it came from and when on the right.
    private func meta(_ moment: ViewerMoment) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let place = moment.place {
                HStack(spacing: 4) {
                    Icon.glyphPin.image
                        .resizable()
                        .frame(width: 20, height: 20)
                        .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 4 }
                    Text(place)
                        .textStyle(.viewerPlace)
                }
                .foregroundStyle(ColorToken.textPrimary.color)
            }
            Spacer(minLength: 8)
            OriginLabel(origin: moment.origin, time: Self.time(moment.captured, date: true), order: .originFirst)
                .textStyle(.viewerMeta)
                .foregroundStyle(ColorToken.textSecondary.color)
                .multilineTextAlignment(.trailing)
        }
    }

    // MARK: Actions

    /// Share, favourite, edit and delete.
    private func actions(_ moment: ViewerMoment) -> some View {
        let tint = (isVideo ? ColorToken.mediaFrame : .textPrimary).color
        return HStack {
            if moment.mediaType == .photo, let url = model.url(moment.composedPath) {
                ShareLink(item: url) {
                    Icon.glyphShare.image.resizable().frame(width: 24, height: 24).foregroundStyle(tint)
                        .frame(width: Size.minimumTapTarget, height: Size.minimumTapTarget)
                }
                .accessibilityLabel(Text("Share", bundle: .module))
                .accessibilityIdentifier("viewer.share")
                .frame(maxWidth: .infinity)
            } else if moment.mediaType == .video {
                // The video is shared as seen: both streams in one file, made when asked for.
                Button {
                    preparingShare = true
                    Task {
                        sharing = await model.exportVideo(moment.id).map(SharedFile.init)
                        preparingShare = false
                    }
                } label: {
                    Group {
                        if preparingShare {
                            ProgressView().tint(tint)
                        } else {
                            Icon.glyphShare.image.resizable().frame(width: 24, height: 24).foregroundStyle(tint)
                        }
                    }
                    .frame(width: Size.minimumTapTarget, height: Size.minimumTapTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(preparingShare)
                .accessibilityLabel(Text("Share", bundle: .module))
                .accessibilityIdentifier("viewer.share")
                .frame(maxWidth: .infinity)
            }
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
            (isVideo ? Color(hex: 0x1F1418).opacity(0.55) : ColorToken.canvas.color)
                .overlay(alignment: .top) {
                    Rectangle().fill((isVideo ? ColorToken.mediaFrame : .textPrimary).color.opacity(0.14)).frame(height: 0.6)
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

/// A moment's caption, then its longer note, both handwritten (M05 Patrick Hand 20); cream on a video.
struct MomentWords: View {
    let moment: ViewerMoment
    let onPhoto: Bool

    var body: some View {
        let color = (onPhoto ? ColorToken.mediaFrame : .textPrimary).color
        VStack(alignment: .leading, spacing: 6) {
            if let title = moment.title {
                Text(title)
                    .textStyle(.dayCaption)
                    .foregroundStyle(color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let note = moment.note {
                Text(note)
                    .textStyle(.dayCaption)
                    .foregroundStyle(color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
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

/// A file handed to the share sheet.
struct SharedFile: Identifiable {
    let url: URL
    var id: URL { url }
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
