import Core
import DesignSystem
import Persistence
import SwiftData
import SwiftUI
import UIKit

/// Today (T01-T07, X01 on iPad): a hello, the latest moment with the capture button on it, the surprise ribbon,
/// this month, On this day and the way into a movie. Nothing here is invented: before the first moment the hero
/// is an empty frame (T01).
struct TodayView: View {
    let model: TodayModel
    @Environment(AppRouter.self) private var router
    @State private var width: CGFloat = 0
    @State private var height: CGFloat = 0
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.layoutDirection) private var readingDirection
    @Environment(\.typefaces) private var typefaces
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Environment(MemoriesPreferences.self) private var memoriesPreferences: MemoriesPreferences?
    @Environment(\.tileMotion) private var motion
    @Environment(\.mediaLibrary) private var library
    /// The hero's latest video, both streams, while Today's motion plays it.
    @State private var heroPlayer: ViewerVideoPlayer?
    @State private var asker = PermissionAsker()
    @Environment(\.permissions) private var permissions
    @State private var heroHalves: CaptureFormat?

    var body: some View {
        ScrollView {
            if isWide { wide } else { narrow }
        }
        .onGeometryChange(for: CGSize.self, of: \.size) { size in
            width = size.width
            height = size.height
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(ColorToken.canvas.color.ignoresSafeArea())
        .permissionExplainers(asker)
        .toolbar(.hidden, for: .navigationBar)
        .navigationTitle(Text("Today", bundle: .module))
        .memoriesDestinations(thisYear: Calendar.current.component(.year, from: model.now))
        .task { await model.refresh() }
        // A prompt fires or expires, a pause ends: the ribbon follows without a tap.
        .task(id: model.surpriseChangesAt) {
            guard let date = model.surpriseChangesAt else { return }
            try? await Task.sleep(for: .seconds(max(1, date.timeIntervalSinceNow + 1)))
            guard !Task.isCancelled else { return }
            await model.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in
            Task { await model.refresh() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.refresh() } }
        }
    }

    // MARK: Layouts

    /// Two columns only where X01 has room for them, iPad landscape; iPad portrait reads better as one column.
    private var isWide: Bool { width >= 1000 }

    /// iPhone (T02) and iPad portrait: one column, the hero and capture first.
    private var narrow: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            greeting(oneLine: false)
                .padding(.top, 18)
            heroAndCapture
                .padding(.top, typeSize.isAccessibilitySize ? 32 : 15)
            ribbon
                .padding(.top, typeSize.isAccessibilitySize ? 20 : 3)
                .frame(maxWidth: .infinity)
            if !model.month.isEmpty {
                monthHeader
                    .padding(.top, 14)
                    .padding(.horizontal, 22)
                monthStrip
            }
            // Every Today board has the movie at the same spot, right under this month; with nothing yet (T01) that
            // is the bottom of the screen. On this day (T06, no hi-fi board) follows it.
            if model.isEmpty { Spacer(minLength: 8) }
            movieCard
                .padding(.top, model.isEmpty ? 0 : 8)
                .padding(.horizontal, 18)
            if showsOnThisDay, let onThisDay = model.onThisDay {
                onThisDaySection(onThisDay)
                    .padding(.top, 32)
                    .padding(.horizontal, 18)
            }
        }
        // On iPhone the wordmark sits up level with the status bar's bottom, as drawn.
        .statusBarLift(13)
        .padding(.bottom, 12)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity, minHeight: height, alignment: .top)
    }

    /// S09 "On this day on Today".
    private var showsOnThisDay: Bool { memoriesPreferences?.value.onThisDayOnToday ?? true }

    /// iPad landscape (X01): the hero on the left; the ribbon, On this day, this month and the movie on the right.
    private var wide: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            greeting(oneLine: true)
                .padding(.top, 18)
            HStack(alignment: .top, spacing: 40) {
                heroAndCapture
                    .frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: 24) {
                    ribbon
                    if showsOnThisDay, let onThisDay = model.onThisDay { onThisDaySection(onThisDay) }
                    if !model.month.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            monthHeader
                            monthGrid
                        }
                    }
                    movieCard
                }
                .frame(width: 400)
                .padding(.top, 8)
            }
            .padding(.top, 26)
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 24)
        .frame(maxWidth: 1180)
        .frame(maxWidth: .infinity)
    }

    // MARK: Header

    /// The wordmark, the Today | Mosaic switch, settings (T02, U10).
    private var header: some View {
        HomeHeader(isWide: isWide)
    }

    /// "WED, NOV 11" and "Your life, in little pieces." with its brush underline and apricot star.
    private func greeting(oneLine: Bool) -> some View {
        let headline = String(appLocalized: "Today headline", bundle: .module)
        let marks = !typeSize.isAccessibilitySize
        // T02's 0.98 line height is tighter than the heading face's own, which one text never draws: each line is its own
        // text, stacked that close. At accessibility sizes lines wrap inside each text, so they keep the font's own.
        let lines = oneLine ? [headline.replacingOccurrences(of: "\n", with: " ")] : headline.components(separatedBy: "\n")
        return VStack(alignment: .leading, spacing: -3) {
            Text(model.now, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
                .textStyle(.labelCaps)
                .padding(.leading, 3)
            VStack(alignment: .leading, spacing: typeSize.isAccessibilitySize ? 0 : TextStyle.displayHero.lineGap(for: typeSize, typefaces: typefaces)) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .textStyle(.displayHero)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
                .overlay(alignment: .bottomLeading) {
                    if marks, !oneLine {
                        Icon.markBrush.image
                            .resizable()
                            .frame(width: 196.3, height: 12.9)
                            .foregroundStyle(ColorToken.actionCoral.color)
                            .offset(x: 50, y: 18)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    Icon.markStarSolo.image
                        .resizable()
                        .frame(width: 39.2, height: 40.4)
                        .foregroundStyle(ColorToken.accentApricot.color)
                        .offset(x: oneLine ? 90 : 39, y: oneLine ? -18 : 0)
                }
        }
        .foregroundStyle(ColorToken.textPrimary.color)
        .padding(.leading, isWide ? 12 : 23)
        .padding(.trailing, 60)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: Hero and capture

    @ViewBuilder
    private var heroAndCapture: some View {
        let ring = !typeSize.isAccessibilitySize
        VStack(spacing: 0) {
            hero
                // The marks sit where the picture has them; the hero reads its caption in the app's direction.
                .environment(\.layoutDirection, readingDirection)
                .overlay(alignment: .topTrailing) {
                    mark(.markTicksA, 26.7, 22.5, ColorToken.accentApricot).offset(x: -6, y: -23)
                }
                .overlay(alignment: .topLeading) {
                    mark(.markHatch, 35, 40.2, ColorToken.accentSage).offset(x: -7, y: 142)
                }
                .overlay(alignment: .bottom) {
                    if ring { captureRing.offset(y: 22) }
                }
                .environment(\.layoutDirection, .leftToRight)
                .padding(.horizontal, isWide ? 0 : 12)
            if ring {
                Button(action: capture) {
                    Text(captureTitle).textStyle(.captureLabel).foregroundStyle(ColorToken.textPrimary.color)
                }
                .buttonStyle(.plain)
                .accessibilityHidden(true)
                .padding(.top, 17)
            } else {
                Button(action: capture) {
                    HStack(spacing: 10) {
                        Icon.cameraCapture.image.resizable().frame(width: 26, height: 20)
                        Text(captureTitle)
                    }
                }
                .buttonStyle(.primary)
                .accessibilityIdentifier("capture")
                .padding(.horizontal, 20)
                .padding(.top, 20)
            }
        }
    }

    @ViewBuilder
    private var hero: some View {
        if let latest = model.latest {
            MomentTileLink(MemoriesRoute.moment(pager(from: latest.id))) {
                MomentHero(
                    photo: heroPicture(latest),
                    selfie: latest.windowPath.map { heroSelfie($0) },
                    caption: model.timeText(latest.captured),
                    place: latest.place.map { Text($0) },
                    tag: latest.origin == .randomPrompt ? Text("surprise", bundle: .module) : nil
                )
                // H.9: held, the whole hero lifts; its video plays inside it, under the frame and caption.
                .tileMotion(
                    latest.id, isVideo: latest.mediaType == .video,
                    still: model.image(latest.thumbnailPath, TodayModel.tilePixels), plays: false
                )
            }
            .task(id: heroPlaying) { await playHero() }
            .onDisappear { stopHero() }
            .buttonStyle(.plain)
            .accessibilityLabel(describe(latest, withSelfie: latest.selfiePath != nil))
            .accessibilityIdentifier("today.hero")
        } else {
            EmptyMomentHero(
                title: Text("Your first moment will live here.", bundle: .module),
                scene: Text("what you see", bundle: .module),
                selfie: Text("you", bundle: .module)
            )
            .accessibilityIdentifier("today.emptyHero")
        }
    }

    /// `Capture / Button`: the 84 pt coral disk in a cream ring, half on the hero.
    private var captureRing: some View {
        Button(action: capture) {
            Icon.cameraCapture.image
                .resizable()
                .frame(width: 40.4, height: 31.1)
                .foregroundStyle(ColorToken.textOnCoral.color)
                .frame(width: 84, height: 84)
                .background(LinearGradient.actionCoral, in: Circle())
                .padding(5)
                .background(
                    Circle()
                        .fill(ColorToken.surfaceCard.color)
                        .shadow(color: Color(hex: 0x4B2938).opacity(0.16), radius: 7, y: 4)
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(captureTitle))
        .accessibilityIdentifier("capture")
    }

    private var captureTitle: LocalizedStringResource {
        if case .ready = model.surprise {
            return LocalizedStringResource("Catch the surprise", bundle: .atURL(Bundle.module.bundleURL))
        }
        if model.isEmpty {
            return LocalizedStringResource("Catch your first moment", bundle: .atURL(Bundle.module.bundleURL))
        }
        return LocalizedStringResource("Catch a moment", bundle: .atURL(Bundle.module.bundleURL))
    }

    private func capture() {
        router.open(.capture(promptID: model.captureRequest()))
    }

    // MARK: Surprise ribbon

    private var ribbon: some View {
        SurpriseRibbon(status: model.surprise, now: model.now) {
            switch model.surprise {
            case .ready: capture()
            case .paused: Task { await model.resume() }
            case .off:
                Task {
                    if await !model.turnOn(request: { await asker.request($0, using: permissions) }), let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            case .onItsWay, .passed: break
            }
        }
        .padding(.horizontal, isWide ? 0 : 18)
    }

    // MARK: This month

    private var monthHeader: some View {
        Button { router.open(.tab(.memories)) } label: {
            HStack {
                Text("Your \(model.now.formatted(.dateTime.month(.wide).locale(AppLanguage.shared.locale)))", bundle: .module)
                    .textStyle(.displaySection)
                    .foregroundStyle(ColorToken.textPrimary.color)
                Spacer(minLength: 8)
                Icon.glyphChevron.image
                    .resizable()
                    .frame(width: 20, height: 20)
                    .foregroundStyle(ColorToken.textPrimary.color)
                    .flipsForRightToLeftLayoutDirection(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topLeading) {
            mark(.markTicksB, 22.5, 16.7, ColorToken.accentCoralMark).offset(x: -10, y: -15)
        }
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("today.month")
    }

    /// Four hand-cut tile shapes in turn, scrolling sideways.
    private var monthStrip: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 2) {
                ForEach(Array(model.month.enumerated()), id: \.element.id) { index, moment in
                    let style = StripTile.styles[index % StripTile.styles.count]
                    MomentTileLink(MemoriesRoute.moment(pager(from: moment.id))) {
                        StripTile(
                            image: model.image(moment.thumbnailPath, TodayModel.tilePixels), style: style,
                            id: moment.id, isVideo: moment.mediaType == .video
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(describe(moment, withSelfie: false))
                }
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 6)
        }
        .scrollIndicators(.hidden)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today.strip")
    }

    /// X01: up to eight hand-cut tiles, four across.
    private var monthGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 4), spacing: 4) {
            ForEach(model.month.prefix(8)) { moment in
                // Each opens its card, as the iPhone's strip does (Andrew, 2026-11-16).
                MomentTileLink(MemoriesRoute.moment(pager(from: moment.id))) {
                    let image = model.image(moment.thumbnailPath, TodayModel.tilePixels)
                    Color(hex: 0xC9B8AA)
                        .aspectRatio(1, contentMode: .fit)
                        .overlay { if let image { Image(uiImage: image).filling() } }
                        .tileMotion(moment.id, isVideo: moment.mediaType == .video, still: image)
                        .clipShape(StripTile.shape(moment.captured.instant))
                        .background(StripTile.shadow(StripTile.shape(moment.captured.instant)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(describe(moment, withSelfie: false))
                .accessibilityIdentifier("today.monthTile")
            }
        }
    }

    // MARK: On this day

    private func onThisDaySection(_ day: OnThisDay) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("On this day", bundle: .module)
                .textStyle(.displaySection)
                .foregroundStyle(ColorToken.textPrimary.color)
                .accessibilityAddTraits(.isHeader)
                .padding(.leading, isWide ? 0 : 6)
            NavigationLink(value: MemoriesRoute.onThisDay) {
                OnThisDayCard(
                    image: model.image(day.cover.picturePath, TodayModel.heroPixels),
                    caption: Text("Years ago and count: \(Text(yearsAgo(day.yearsAgo))) · \(Text("\(day.count) moments", bundle: .module))", bundle: .module)
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("today.onThisDay")
        }
    }

    private func yearsAgo(_ years: Int) -> LocalizedStringResource {
        LocalizedStringResource("\(years) years ago", bundle: .atURL(Bundle.module.bundleURL))
    }

    // MARK: Movie

    private var movieCard: some View {
        Button { router.open(.newMovie(nil)) } label: {
            HStack(spacing: 0) {
                Icon.glyphFilm.image
                    .resizable()
                    .frame(width: 42, height: 36)
                    .foregroundStyle(ColorToken.textLink.color)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Make my movie", bundle: .module)
                        .textStyle(.cardTitle)
                        .foregroundStyle(ColorToken.textPrimary.color)
                    Group {
                        if model.isEmpty {
                            Text("Your story starts with one moment", bundle: .module)
                        } else {
                            Text("\(model.count) moments saved", bundle: .module)
                        }
                    }
                    .textStyle(.rowCaption)
                    .foregroundStyle(ColorToken.textBody.color)
                }
                .padding(.leading, 18)
                Spacer(minLength: 8)
                // Nothing to open yet: no chevron (T01).
                if !model.isEmpty {
                    Icon.glyphChevron.image
                        .resizable()
                        .frame(width: 20, height: 20)
                        .foregroundStyle(ColorToken.textPrimary.color)
                        .flipsForRightToLeftLayoutDirection(true)
                }
            }
            .padding(.leading, 23)
            .padding(.trailing, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 65, alignment: .leading)
            .background(MovieBlob().fill(ColorToken.accentPeach.color))
            .contentShape(Rectangle())
        }
        // T01 dims the whole card to 0.6 once; the plain style would dim a disabled label again.
        .buttonStyle(MovieCardButtonStyle())
        .disabled(model.isEmpty)
        .opacity(model.isEmpty ? 0.6 : 1)
        .accessibilityIdentifier("today.movie")
        .overlay(alignment: .topTrailing) {
            mark(.markTicksC, 34.8, 21.7, ColorToken.accentCoralMark).offset(x: 14, y: -9)
        }
    }

    // MARK: Helpers

    private func pager(from id: UUID) -> MomentPager { model.pager(from: id) }

    /// H.9: a video's main stream plays in the hero; its selfie window stays a still.
    private func heroPicture(_ latest: MomentSummary) -> HeroMedia {
        guard latest.mediaType == .video, let image = model.image(latest.picturePath, TodayModel.heroPixels) else {
            return media(latest.picturePath, TodayModel.heroPixels)
        }
        return .view(AnyView(
            Image(uiImage: image).filling()
                .overlay { if let heroPlayer, heroPlayer.isReady { HeroVideo(player: heroPlayer, halves: heroHalves) } }
        ))
    }

    /// The hero's selfie window: its still, with the selfie stream playing over it while the hero plays.
    private func heroSelfie(_ path: String) -> HeroMedia {
        guard let heroPlayer, heroPlayer.isReady, heroPlayer.hasSelfie, let image = model.image(path, TodayModel.selfiePixels) else {
            return media(path, TodayModel.selfiePixels)
        }
        return .view(AnyView(Image(uiImage: image).filling().overlay { PlayerLayerView(player: heroPlayer.selfie).allowsHitTesting(false) }))
    }

    /// H.9: the latest moment's video while Today's motion plays it (on screen, among the four, motion on).
    private var heroPlaying: UUID? {
        guard let latest = model.latest, latest.mediaType == .video, motion?.plays(latest.id) == true else { return nil }
        return latest.id
    }

    /// Both streams, silent, round and round (Andrew, 2026-11-16: the hero is the one tile whose selfie plays).
    private func playHero() async {
        stopHero()
        guard let id = heroPlaying, let library, let loaded = await library.loop(id, withSelfie: true), !Task.isCancelled else { return }
        let player = ViewerVideoPlayer(duration: loaded.video.timing.duration, silent: true)
        await player.load(main: loaded.main, selfie: loaded.selfie)
        guard !Task.isCancelled else { return player.stop() }
        heroHalves = loaded.video.timing.halves
        heroPlayer = player
        player.play()
    }

    private func stopHero() {
        heroPlayer?.stop()
        heroPlayer = nil
    }

    private func media(_ path: String?, _ size: Int) -> HeroMedia {
        model.image(path, size).map { .image(Image(uiImage: $0)) } ?? .placeholder
    }

    /// "Photo, Today, 2:37 PM, Yerevan, with selfie" (A07).
    private func describe(_ moment: MomentSummary, withSelfie: Bool) -> Text {
        var text = moment.mediaType == .video ? Text("Video", bundle: .module) : Text("Photo", bundle: .module)
        text = text + Text(verbatim: ", ") + model.timeText(moment.captured)
        if let place = moment.place { text = text + Text(verbatim: ", ") + Text(place) }
        if moment.origin == .randomPrompt { text = text + Text(verbatim: ", ") + Text("surprise", bundle: .module) }
        if withSelfie { text = text + Text(verbatim: ", ") + Text("with selfie", bundle: .module) }
        return text
    }

    private func mark(_ icon: Icon, _ width: CGFloat, _ height: CGFloat, _ color: ColorToken) -> some View {
        icon.image
            .resizable()
            .frame(width: width, height: height)
            .foregroundStyle(color.color)
            .accessibilityHidden(true)
    }
}

private struct MovieCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.7 : 1)
    }
}
