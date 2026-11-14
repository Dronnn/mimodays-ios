import Core
import DesignSystem
import SwiftData
import SwiftUI
import UIKit

/// Today (T01-T07, X01 on iPad): a hello, the latest moment with the capture button on it, the surprise ribbon,
/// this month, On this day and the way into a movie. Nothing here is invented: before the first moment the hero
/// is an empty frame (T01).
struct TodayView: View {
    let model: TodayModel
    @Environment(AppRouter.self) private var router
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var width: CGFloat = 0
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ScrollView {
            if isWide { wide } else { narrow }
        }
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { width = $0 }
        .scrollBounceBehavior(.basedOnSize)
        .background(ColorToken.canvas.color.ignoresSafeArea())
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
                .padding(.top, typeSize.isAccessibilitySize ? 32 : 26)
            ribbon
                .padding(.top, typeSize.isAccessibilitySize ? 20 : 3)
                .frame(maxWidth: .infinity)
            if !model.month.isEmpty {
                monthHeader
                    .padding(.top, 14)
                    .padding(.horizontal, 22)
                monthStrip
                    .padding(.top, 5)
            }
            if let onThisDay = model.onThisDay {
                onThisDaySection(onThisDay)
                    .padding(.top, 32)
                    .padding(.horizontal, 18)
            }
            movieCard
                .padding(.top, model.onThisDay == nil ? 13 : 28)
                .padding(.horizontal, 18)
        }
        // On iPhone the wordmark sits up level with the status bar's bottom, as drawn.
        .padding(.top, sizeClass == .compact ? -13 : 0)
        .padding(.bottom, 16)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity)
    }

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
                    if let onThisDay = model.onThisDay { onThisDaySection(onThisDay) }
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

    /// The wordmark sets the height; the gear hangs a little lower, beside it (T02).
    private var header: some View {
        ZStack {
            Icon.brandWordmark.image.resizable().foregroundStyle(ColorToken.textPrimary.color)
            Icon.brandWordmarkStar.image.resizable().foregroundStyle(ColorToken.actionCoral.color)
        }
        .frame(width: 103.7, height: 33)
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityElement()
        .accessibilityLabel(Text(verbatim: "MimoDays"))
        .accessibilityAddTraits(.isHeader)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .topTrailing) {
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
            .offset(y: 2)
        }
        .padding(.leading, isWide ? 12 : 25)
        .padding(.trailing, isWide ? 8 : 19)
    }

    /// "WED, NOV 11" and "Your life, in little pieces." with its brush underline and apricot star.
    private func greeting(oneLine: Bool) -> some View {
        let headline = String(localized: "Today headline", bundle: .module)
        let marks = !typeSize.isAccessibilitySize
        return VStack(alignment: .leading, spacing: 3) {
            Text(model.now, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
                .textStyle(.labelCaps)
                .padding(.leading, 3)
            Text(oneLine ? headline.replacingOccurrences(of: "\n", with: " ") : headline)
                .textStyle(.displayHero)
                .fixedSize(horizontal: false, vertical: true)
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
                        Icon.glyphCamera.image.resizable().frame(width: 26, height: 20)
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
            NavigationLink(value: MemoriesRoute.moment(pager(from: latest.id))) {
                MomentHero(
                    photo: media(latest.mainPath, TodayModel.heroPixels),
                    selfie: latest.selfiePath.map { media($0, TodayModel.selfiePixels) },
                    caption: model.timeText(latest.captured),
                    place: latest.place.map { Text($0) },
                    tag: latest.origin == .randomPrompt ? Text("surprise", bundle: .module) : nil
                )
            }
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
            Icon.glyphCamera.image
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
                    if await !model.turnOn(), let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
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
                Text("Your \(model.now.formatted(.dateTime.month(.wide)))", bundle: .module)
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
                    NavigationLink(value: MemoriesRoute.moment(pager(from: moment.id))) {
                        StripTile(image: model.image(moment.thumbnailPath, TodayModel.tilePixels), style: style)
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

    /// X01: up to eight rounded tiles, four across.
    private var monthGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 4), spacing: 4) {
            ForEach(model.month.prefix(8)) { moment in
                Color(hex: 0xC9B8AA)
                    .aspectRatio(1, contentMode: .fit)
                    .overlay {
                        if let image = model.image(moment.thumbnailPath, TodayModel.tilePixels) {
                            Image(uiImage: image).resizable().scaledToFill()
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityElement()
                    .accessibilityLabel(describe(moment, withSelfie: false))
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
            Button { router.open(.tab(.memories)) } label: {
                OnThisDayCard(
                    image: model.image(day.cover.mainPath, TodayModel.heroPixels),
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
        Button { router.open(.tab(.movies)) } label: {
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
                Icon.glyphChevron.image
                    .resizable()
                    .frame(width: 20, height: 20)
                    .foregroundStyle(ColorToken.textPrimary.color)
                    .flipsForRightToLeftLayoutDirection(true)
            }
            .padding(.leading, 23)
            .padding(.trailing, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 65, alignment: .leading)
            .background(MovieBlob().fill(ColorToken.accentPeach.color))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(model.isEmpty)
        .opacity(model.isEmpty ? 0.6 : 1)
        .accessibilityIdentifier("today.movie")
        .overlay(alignment: .topTrailing) {
            mark(.markTicksC, 34.8, 21.7, ColorToken.accentCoralMark).offset(x: 14, y: -9)
        }
    }

    // MARK: Helpers

    /// The latest moment, then this month's: what Today shows, to swipe through.
    private func pager(from id: UUID) -> MomentPager {
        var ids = model.latest.map { [$0.id] } ?? []
        ids += model.month.map(\.id).filter { !ids.contains($0) }
        return MomentPager(ids: ids, start: id)
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
