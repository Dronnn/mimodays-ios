import Core
import DesignSystem
import Persistence
import SwiftData
import SwiftUI

struct MoviePageScreen: View {
    let projectID: UUID
    @Environment(\.mediaLibrary) private var library

    var body: some View {
        if let library, let project = MovieStore.project(projectID, in: library.context) {
            MoviePageHost(project: project, library: library)
        }
    }
}

private struct MoviePageHost: View {
    let project: MovieProject
    let library: MediaLibrary
    @State private var tiles: MemoriesModel

    init(project: MovieProject, library: MediaLibrary) {
        self.project = project
        self.library = library
        _tiles = State(initialValue: MemoriesModel(context: library.context, store: library.store, thumbnails: library.thumbnails))
    }

    var body: some View { MoviePageView(project: project, library: library, tiles: tiles) }
}

/// F15: a rendered movie - play it, share or save it; edit, duplicate or rename its project; delete both.
struct MoviePageView: View {
    let project: MovieProject
    let library: MediaLibrary
    let tiles: MemoriesModel
    @Environment(AppRouter.self) private var router
    @State private var watching = false
    @State private var renaming = false
    @State private var name = ""
    @State private var deleting = false
    @State private var saved = false
    @State private var problem: Text?
    @State private var asker = PermissionAsker()
    @Environment(\.permissions) private var permissions

    private var store: MovieStore { MovieStore(context: library.context, store: library.store) }
    private var coverID: UUID? { MovieStore.liveClips(of: project).first?.moment?.id }
    private var url: URL? { project.render.flatMap { try? library.store.url(for: $0.relativePath) } }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                BackTitleBar(back: Text("Movies", bundle: .module)) {
                    if !router.moviesPath.isEmpty { router.moviesPath.removeLast() }
                }
                more
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    cover.padding(.horizontal, 16).padding(.top, 8)
                    Text(project.title)
                        .textStyle(TextStyle(.fraunces, size: 30, weight: 600, tracking: -0.4, relativeTo: .title1, maximumScale: 1.35))
                        .foregroundStyle(ColorToken.textPrimary.color)
                        .padding(.horizontal, 18)
                        .padding(.top, 14)
                        .accessibilityAddTraits(.isHeader)
                    if let render = project.render {
                        Text(Self.meta(render, project.aspectRatio))
                            .textStyle(.noteMeta)
                            .foregroundStyle(ColorToken.textSecondary.color)
                            .padding(.horizontal, 20)
                            .padding(.top, 6)
                    }
                    HStack(spacing: 16) {
                        if let url {
                            ShareLink(item: url) {
                                Label { Text("Share", bundle: .module) } icon: { Icon.glyphShare.image.resizable().frame(width: 20, height: 20) }
                            }
                            .buttonStyle(HalfButtonStyle())
                            .accessibilityIdentifier("movie.share")
                        }
                        Button { Task { await save() } } label: {
                            Label {
                                saved ? Text("Saved", bundle: .module) : Text("Save", bundle: .module)
                            } icon: {
                                (saved ? Icon.glyphCheck : Icon.glyphDownload).image.resizable().frame(width: 20, height: 20)
                            }
                        }
                        .buttonStyle(HalfButtonStyle())
                        .disabled(url == nil || saved)
                        .accessibilityIdentifier("movie.save")
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 15)
                    Text("Project", bundle: .module)
                        .textStyle(.labelCaps)
                        .foregroundStyle(ColorToken.textSecondary.color)
                        .padding(.horizontal, 22)
                        .padding(.top, 24)
                        .accessibilityAddTraits(.isHeader)
                    projectCard.padding(.horizontal, 16).padding(.top, 6)
                    Button { deleting = true } label: {
                        Text("Delete movie and project", bundle: .module)
                            .textStyle(.rowTitle)
                            .foregroundStyle(ColorToken.textLink.color)
                            .frame(minHeight: Size.minimumTapTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 18)
                    .padding(.top, 16)
                    .accessibilityIdentifier("movie.delete")
                    Text("Copies saved to Photos or Files stay there.", bundle: .module)
                        .textStyle(TextStyle(.nunito, size: 13, weight: 500, relativeTo: .footnote))
                        .foregroundStyle(ColorToken.textSecondary.color)
                        .padding(.horizontal, 18)
                }
                .padding(.bottom, 24)
                .frame(maxWidth: 640, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
        .background(ColorToken.canvas.color.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .task { if let coverID { await tiles.load(coverID) } }
        .fullScreenCover(isPresented: $watching) {
            if let url { RenderedMoviePlayer(url: url) }
        }
        .alert(Text("Rename movie", bundle: .module), isPresented: $renaming) {
            TextField(text: $name) { Text("Movie title", bundle: .module) }
            Button(role: .cancel) {} label: { Text("Cancel", bundle: .module) }
            Button { try? store.rename(project, to: name) } label: { Text("Rename", bundle: .module) }
        }
        .confirmationDialog(Text("Delete this movie and its project?", bundle: .module), isPresented: $deleting, titleVisibility: .visible) {
            Button(role: .destructive) {
                try? store.delete(project)
                router.moviesPath = []
            } label: { Text("Delete", bundle: .module) }
        } message: {
            Text("Copies saved to Photos or Files stay there.", bundle: .module)
        }
        .permissionExplainers(asker)
        .alert(Text("Couldn't save to Photos", bundle: .module), isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })) {
            Button { problem = nil } label: { Text("OK", bundle: .module) }
        } message: {
            problem
        }
    }

    /// `Movie / Cover`: the first picture in its hand-cut 370×230 frame, Play over it.
    private var cover: some View {
        Button { watching = true } label: {
            Poster(image: coverID.flatMap { tiles.images[$0] })
                .aspectRatio(370 / 230, contentMode: .fit)
                .clipShape(DayCardBlob())
                .overlay { PlayDisc() }
        }
        .buttonStyle(.plain)
        .disabled(url == nil)
        .accessibilityLabel(Text("Play the movie", bundle: .module))
        .accessibilityIdentifier("movie.play")
    }

    /// The ••• menu: the same things as on the page.
    private var more: some View {
        Menu {
            Button { router.moviesPath.append(.editor(project.id)) } label: { Text("Edit", bundle: .module) }
            Button(action: duplicate) { Text("Duplicate", bundle: .module) }
            Button(action: rename) { Text("Rename", bundle: .module) }
            Button(role: .destructive) { deleting = true } label: { Text("Delete movie and project", bundle: .module) }
        } label: {
            Icon.glyphMore.image
                .resizable()
                .frame(width: 24, height: 24)
                .foregroundStyle(ColorToken.textPrimary.color)
                .frame(width: Size.minimumTapTarget, height: Size.minimumTapTarget)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(Text("More", bundle: .module))
        .accessibilityIdentifier("movie.more")
        .padding(.trailing, 6)
    }

    private var projectCard: some View {
        VStack(spacing: 0) {
            row(.glyphScissors, Text("Edit", bundle: .module), detail: Text("Changes make a new version", bundle: .module), id: "movie.edit") {
                router.moviesPath.append(.editor(project.id))
            }
            separator
            row(.glyphCollection, Text("Duplicate", bundle: .module), id: "movie.duplicate", action: duplicate)
            separator
            row(.glyphText, Text("Rename", bundle: .module), id: "movie.rename", action: rename)
        }
        .background(ColorToken.surfaceCard.color, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var separator: some View {
        Color(hex: 0x4B2938).opacity(0.12).frame(height: 0.6).padding(.leading, 64)
    }

    private func row(_ icon: Icon, _ title: Text, detail: Text? = nil, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                icon.image
                    .resizable()
                    .frame(width: 20, height: 20)
                    .foregroundStyle(ColorToken.textPrimary.color)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(ColorToken.accentPeach.color))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    title.textStyle(.rowTitle).foregroundStyle(ColorToken.textPrimary.color)
                    if let detail {
                        detail
                            .textStyle(TextStyle(.nunito, size: 13, weight: 500, relativeTo: .footnote))
                            .foregroundStyle(ColorToken.textSecondary.color)
                    }
                }
                Spacer(minLength: 8)
                Icon.glyphChevron.image
                    .resizable()
                    .frame(width: 20, height: 20)
                    .foregroundStyle(ColorToken.textPrimary.color)
                    .flipsForRightToLeftLayoutDirection(true)
                    .accessibilityHidden(true)
            }
            .padding(.leading, 14)
            .padding(.trailing, 14)
            .frame(minHeight: 52)
            .padding(.vertical, detail == nil ? 0 : 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(id)
    }

    private func duplicate() {
        guard let copy = try? store.duplicate(project) else { return }
        router.moviesPath = [.editor(copy.id)]
    }

    private func rename() {
        name = project.title
        renaming = true
    }

    private func save() async {
        guard let url else { return }
        guard await asker.request(.photoLibrary, using: permissions) != .notDetermined else { return }
        do {
            try await MovieFiles.saveToPhotos(url)
            saved = true
        } catch MovieFiles.Failure.notAllowed {
            problem = Text("Allow MimoDays to add to your photos in Settings.", bundle: .module)
        } catch {
            problem = Text("Something went wrong. Try again.", bundle: .module)
        }
    }

    /// "Movie · 1:02 · 9:16 · 1080p · made Oct 1".
    static func meta(_ render: MovieRender, _ shape: MovieAspectRatio) -> String {
        let length = Duration.seconds(render.duration.rounded()).formatted(.time(pattern: .minuteSecond))
        let quality = switch render.resolution {
        case .p720: "720p"
        case .p1080: "1080p"
        case .p2160: String(localized: "4K", bundle: .module)
        }
        let made = render.renderedAt.formatted(.dateTime.month(.abbreviated).day())
        return String(
            localized: "Movie · \(length) · \(shape.label) · \(quality) · made \(made)", bundle: .module,
            comment: "F15: a rendered movie's length, shape, quality and the day it was made"
        )
    }
}

/// `Button / Half`: a glyph and a word on the hand-cut chip shape, half the width, 44 pt tall.
struct HalfButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .labelStyle(.titleAndIcon)
            .textStyle(TextStyle(.nunito, size: 15, weight: 700, relativeTo: .subheadline, maximumScale: 1.35))
            .foregroundStyle(ColorToken.textPrimary.color)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background { ColorToken.surfaceChip.color.mask { Icon.shapeButton.image.resizable() } }
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.45)
            .contentShape(Rectangle())
    }
}
