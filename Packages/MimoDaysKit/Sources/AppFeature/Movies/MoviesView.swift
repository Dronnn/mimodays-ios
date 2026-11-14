import Core
import DesignSystem
import Persistence
import SwiftData
import SwiftUI

struct MoviesScreen: View {
    @Environment(\.mediaLibrary) private var library

    var body: some View {
        if let library { MoviesHost(model: MoviesModel(library: library)) }
    }
}

private struct MoviesHost: View {
    @State var model: MoviesModel
    var body: some View { MoviesView(model: model) }
}

/// F01 / F01e: last month when it's ready, drafts, rendered movies; + and Make a movie start a new one.
struct MoviesView: View {
    let model: MoviesModel
    @Environment(AppRouter.self) private var router
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                if model.isEmpty {
                    emptyState.padding(.top, 92)
                } else {
                    if let suggestion = model.suggestion {
                        SuggestionCard(suggestion: suggestion, make: { model.makeSuggestion() }, dismiss: model.dismissSuggestion)
                            .padding(.horizontal, 16)
                            .padding(.top, 22)
                    }
                    if !model.drafts.isEmpty { drafts }
                    if !model.movies.isEmpty { movies }
                }
            }
            // On iPhone the buttons sit level with the status bar's bottom, as drawn (as Memories).
            .padding(.top, sizeClass == .compact ? -9 : 0)
            .padding(.bottom, 24)
            .frame(maxWidth: 1180)
            .frame(maxWidth: .infinity)
        }
        .background(ColorToken.canvas.color.ignoresSafeArea())
        .navigationTitle(Text("Movies", bundle: .module))
        .toolbar(.hidden, for: .navigationBar)
        .fullScreenCover(item: Binding(get: { router.newMovie }, set: { router.newMovie = $0 })) { request in
            NewMovieScreen(source: request.source) { _ in
                router.newMovie = nil
                model.refresh()
            }
        }
        .task { model.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in model.refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.refresh() }
        }
    }

    // MARK: Header

    /// + and settings in ringed circles, then "Movies" with its brush underline and apricot star.
    private var header: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 9) {
                Spacer()
                Button { router.open(.newMovie(nil)) } label: {
                    ringed(.glyphPlus)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("New movie", bundle: .module))
                .accessibilityIdentifier("movies.new")
                Button { router.open(.settings) } label: {
                    ringed(.glyphGear)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Settings", bundle: .module))
                .accessibilityIdentifier("settings")
            }
            .padding(.trailing, 19)
            Text("Movies", bundle: .module)
                .textStyle(.screenTitle)
                .foregroundStyle(ColorToken.textPrimary.color)
                .fixedSize(horizontal: false, vertical: true)
                .overlay(alignment: .bottomLeading) {
                    Icon.markBrush.image
                        .resizable()
                        .frame(width: 120, height: 10.5)
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

    /// A 22 pt glyph in a 40 pt ringed circle, 44 pt to tap.
    private func ringed(_ icon: Icon) -> some View {
        icon.image
            .resizable()
            .frame(width: 22, height: 22)
            .foregroundStyle(ColorToken.textPrimary.color)
            .frame(width: 40, height: 40)
            .overlay(Circle().strokeBorder(ColorToken.textPrimary.color, lineWidth: 1.3))
            .frame(width: Size.minimumTapTarget, height: Size.minimumTapTarget)
            .contentShape(Circle())
    }

    // MARK: Sections

    private var drafts: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle(Text("Drafts", bundle: .module))
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8, alignment: .top), GridItem(.flexible(), alignment: .top)], spacing: 18) {
                ForEach(Array(model.drafts.enumerated()), id: \.element.id) { index, draft in
                    DraftCard(draft: draft, image: draft.coverID.flatMap { model.tiles.images[$0] }, column: index % 2, now: model.now)
                        .task { if let id = draft.coverID { await model.tiles.load(id) } }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
        }
        .padding(.top, 18)
    }

    private var movies: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle(Text("Movies", bundle: .module))
            VStack(spacing: 12) {
                ForEach(model.movies) { movie in
                    MovieRow(movie: movie, image: movie.coverID.flatMap { model.tiles.images[$0] })
                        .task { if let id = movie.coverID { await model.tiles.load(id) } }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
        }
        .padding(.top, 18)
    }

    private func sectionTitle(_ text: Text) -> some View {
        text
            .textStyle(.librarySection)
            .foregroundStyle(ColorToken.textPrimary.color)
            .accessibilityAddTraits(.isHeader)
            .padding(.horizontal, 20)
    }

    // MARK: Empty

    /// F01e: what a movie is, and the one way to start.
    private var emptyState: some View {
        VStack(spacing: 0) {
            ExplainerArt(glyph: .explainerFilm)
            Text("No movies yet", bundle: .module)
                .textStyle(.emptyTitle)
                .foregroundStyle(ColorToken.textPrimary.color)
                .padding(.top, 18)
                .accessibilityAddTraits(.isHeader)
            Text("Turn a month, a trip or a whole year of moments into a short film.", bundle: .module)
                .textStyle(.emptyBody)
                .foregroundStyle(ColorToken.textBody.color)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 250)
                .padding(.top, 8)
            Button { router.open(.newMovie(nil)) } label: {
                Text("Make a movie", bundle: .module)
            }
            .buttonStyle(.primary)
            .padding(.horizontal, 20)
            .padding(.top, 27)
            .accessibilityIdentifier("movies.make")
        }
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Pieces

/// `Movie / Suggestion`: last month on the green card, Make it and Not now.
struct SuggestionCard: View {
    let suggestion: MovieSuggestion
    let make: () -> Void
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Icon.markStarSmall.image
                    .resizable()
                    .frame(width: 17, height: 17.5)
                    .foregroundStyle(ColorToken.accentCoralMark.color)
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 2 }
                    .accessibilityHidden(true)
                Text("\(MoviesModel.monthName(suggestion.month)) is ready", bundle: .module)
                    .textStyle(.suggestionTitle)
                    .foregroundStyle(ColorToken.textPrimary.color)
                    .accessibilityAddTraits(.isHeader)
            }
            Text(summary)
                .textStyle(.pageIntro)
                .foregroundStyle(ColorToken.textBody.color)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 7)
            HStack(spacing: 0) {
                Button(action: make) {
                    Text("Make it", bundle: .module)
                }
                .buttonStyle(SmallPrimaryButtonStyle())
                .accessibilityIdentifier("movies.suggestion.make")
                Button(action: dismiss) {
                    Text("Not now", bundle: .module)
                        .textStyle(.smallAction)
                        .foregroundStyle(ColorToken.textPrimary.color)
                        .padding(.horizontal, 18)
                        .frame(minHeight: Size.minimumTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("movies.suggestion.dismiss")
            }
            .padding(.top, 9)
        }
        .padding(.leading, 18)
        .padding(.trailing, 20)
        .padding(.top, 15)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { ColorToken.accentMint.color.mask { Icon.shapeButton.image.resizable() } }
        .accessibilityElement(children: .contain)
    }

    private var summary: String {
        let minutes = max(1, Int((suggestion.seconds / 60).rounded()))
        let moments = String(localized: "\(suggestion.candidates.count) moments from \(suggestion.days) days.", bundle: .module)
        let length = String(localized: "About \(minutes) minutes.", bundle: .module)
        return "\(moments) \(length)"
    }
}

/// `Button / Small primary`: 120×38, the coral shape with a Fraunces label.
struct SmallPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .textStyle(.buttonSmall)
            .foregroundStyle(ColorToken.textOnCoral.color)
            .padding(.horizontal, 22)
            .frame(minWidth: 120, minHeight: 38)
            .background {
                LinearGradient.actionCoral
                    .mask { Icon.shapeButton.image.resizable() }
                    .shadow(color: ColorToken.textLink.color.opacity(0.25), radius: 6, y: 4)
            }
            .frame(minHeight: Size.minimumTapTarget)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .contentShape(Rectangle())
    }
}

/// `Movie / Draft card`: the cover in its hand-cut frame with "Draft", the name and when it was last edited.
struct DraftCard: View {
    let draft: MovieCard
    let image: UIImage?
    /// The two columns have their own frames, as drawn.
    let column: Int
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            cover
                .overlay(alignment: .topLeading) {
                    Text("Draft", bundle: .module)
                        .textStyle(.coverBadge)
                        .foregroundStyle(ColorToken.textLink.color)
                        .padding(.horizontal, 10)
                        .frame(minHeight: 22)
                        .background(ColorToken.surfaceCard.color, in: Capsule())
                        .padding(.leading, 11)
                        .padding(.top, 12)
                }
            Text(draft.title)
                .textStyle(.rowTitle)
                .foregroundStyle(ColorToken.textPrimary.color)
                .padding(.top, 10)
                .padding(.leading, 2)
            MovieCard.edited(draft.updatedAt, now: now)
                .textStyle(.sectionCount)
                .foregroundStyle(ColorToken.textSecondary.color)
                .padding(.top, 1)
                .padding(.leading, 2)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("movies.draft")
    }

    private var cover: some View {
        Color(hex: 0xC9B8AA)
            .aspectRatio(177 / 102, contentMode: .fit)
            .overlay {
                if let image { Image(uiImage: image).filling() }
            }
            .clipShape(column == 0 ? AnyShape(DraftCoverBlobA()) : AnyShape(DraftCoverBlobB()))
        .contentShape(column == 0 ? AnyShape(DraftCoverBlobA()) : AnyShape(DraftCoverBlobB()))
    }
}

/// `Movie / Row`: the poster, the name, length · shape · when it was made, and Play.
struct MovieRow: View {
    let movie: MovieCard
    let image: UIImage?

    var body: some View {
        HStack(spacing: 14) {
            Group {
                if let image {
                    Image(uiImage: image).filling()
                } else {
                    Color(hex: 0xB9A89A)
                }
            }
            .frame(width: 98, height: 66)
            .clipShape(MoviePosterBlob())
            VStack(alignment: .leading, spacing: 4) {
                Text(movie.title)
                    .textStyle(.rowTitle)
                    .foregroundStyle(ColorToken.textPrimary.color)
                if let render = movie.render {
                    MovieCard.meta(render, movie.aspectRatio)
                        .textStyle(.sectionCount)
                        .foregroundStyle(ColorToken.textSecondary.color)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Icon.glyphPlay.image
                .resizable()
                .frame(width: 18, height: 18)
                .foregroundStyle(ColorToken.textPrimary.color)
                .frame(width: 36, height: 36)
                .background(ColorToken.accentPeach.color, in: Circle())
                .accessibilityHidden(true)
        }
        .frame(minHeight: 68)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("movies.movie")
    }
}

extension MovieCard {
    /// "Edited 2 days ago" within a week, then "Edited Oct 2".
    static func edited(_ date: Date, now: Date) -> Text {
        let relative = RelativeDateTimeFormatter()
        relative.dateTimeStyle = .named
        let when = now.timeIntervalSince(date) < 7 * 86_400
            ? relative.localizedString(for: date, relativeTo: now)
            : date.formatted(.dateTime.month(.abbreviated).day())
        return Text("Edited \(when)", bundle: .module)
    }

    /// "1:02 · 9:16 · Oct 1".
    static func meta(_ render: MovieRender, _ shape: MovieAspectRatio) -> Text {
        let length = Duration.seconds(render.duration.rounded()).formatted(.time(pattern: .minuteSecond))
        let made = render.renderedAt.formatted(.dateTime.month(.abbreviated).day())
        return Text("\(length) · \(shape.label) · \(made)", bundle: .module)
    }
}

extension MovieAspectRatio {
    /// "9:16", as on F04's options.
    var label: String {
        switch self {
        case .portrait9x16: "9:16"
        case .landscape16x9: "16:9"
        case .square1x1: "1:1"
        }
    }
}
