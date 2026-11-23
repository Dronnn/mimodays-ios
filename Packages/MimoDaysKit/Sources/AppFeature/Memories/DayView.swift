import Core
import DesignSystem
import Foundation
import Observation
import os
import Persistence
import SwiftData
import SwiftUI

/// One day's moments, oldest first, with their pictures decoded small (M04).
@MainActor
@Observable
final class DayModel {
    let day: Int
    private(set) var moments: [MomentSummary] = []
    /// P8.3: the whole day hidden from memories.
    private(set) var isHidden = false
    /// The moments an automatic movie of the day takes: hidden ones stay out (P8.3).
    private(set) var movieMoments = 0
    /// A hide or show of the day that couldn't be saved, for "Try again".
    private(set) var failedVisibility: Bool?
    private(set) var images: [String: UIImage] = [:]

    static let photoPixels = 1000
    static let selfiePixels = 240

    private let context: ModelContext
    private let store: MediaStore
    private let thumbnails: ThumbnailPipeline
    private let logger = Logger(subsystem: "MimoDays", category: "Day")

    convenience init(day: Int, library: MediaLibrary) {
        self.init(day: day, context: library.context, store: library.store, thumbnails: library.thumbnails)
    }

    init(day: Int, context: ModelContext, store: MediaStore, thumbnails: ThumbnailPipeline) {
        self.day = day
        self.context = context
        self.store = store
        self.thumbnails = thumbnails
    }

    /// The places of the day, each once, in the order they were visited.
    var places: [String] {
        var seen = Set<String>()
        return moments.compactMap(\.place).filter { seen.insert($0).inserted }
    }

    func refresh() async {
        let day = day
        let descriptor = FetchDescriptor<Moment>(
            predicate: #Predicate { $0.deletedAt == nil && $0.localDay == day },
            sortBy: [SortDescriptor(\.capturedAt)]
        )
        let visibility = MemoryVisibility(context: context)
        isHidden = visibility.isDayHidden(day)
        do {
            let fetched = try context.fetch(descriptor)
            moments = fetched.map(MomentSummary.init)
            movieMoments = visibility.visible(fetched).count
        } catch {
            logger.error("Reading the day failed: \(error.localizedDescription, privacy: .public)")
        }
        for moment in moments {
            await load(moment.picturePath, Self.photoPixels)
            await load(moment.windowPath, Self.selfiePixels)
        }
    }

    /// Hide this day from memories (after BB04's confirmation), or Show this day in memories.
    func setHidden(_ hidden: Bool) {
        failedVisibility = nil
        do {
            try MemoryVisibility.setDayHidden(hidden, day, in: context)
            isHidden = hidden
        } catch {
            context.rollback()
            failedVisibility = hidden
            logger.error("Hiding the day failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// After the alert's own dismissal, which clears the failure: a second one brings a fresh alert.
    func retryVisibility() {
        guard let hidden = failedVisibility else { return }
        Task { self.setHidden(hidden) }
    }

    func dismissVisibilityFailure() {
        failedVisibility = nil
    }

    func image(_ path: String?) -> UIImage? {
        path.flatMap { images[$0] }
    }

    private func load(_ path: String?, _ size: Int) async {
        guard let path, images[path] == nil, let url = try? store.url(for: path),
              let image = try? await thumbnails.thumbnail(for: url, maxPixelSize: size) else { return }
        images[path] = UIImage(cgImage: image)
    }
}

/// A day from anywhere in the app; keeps its model while on screen.
struct DayScreen: View {
    let day: Int
    let thisYear: Int
    @Environment(\.mediaLibrary) private var library

    var body: some View {
        if let library {
            ModelHost({ DayModel(day: day, library: library) }) { DayHost(model: $0, thisYear: thisYear) }
        }
    }
}

private struct DayHost: View {
    @State var model: DayModel
    let thisYear: Int

    var body: some View {
        DayView(model: model, thisYear: thisYear)
    }
}

/// M04: a day's moments as cards, each with its selfie window, time and caption.
struct DayView: View {
    let model: DayModel
    /// The title leaves the year out within this one.
    let thisYear: Int
    @Environment(AppRouter.self) private var router: AppRouter?
    /// BB04: "Hide this day from memories?".
    @State private var confirmsHiding = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                summary
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                if model.isHidden {
                    HiddenFromMemoriesChip()
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .accessibilityIdentifier("day.hiddenState")
                }
                ForEach(model.moments) { moment in
                    MomentTileLink(MemoriesRoute.moment(MomentPager(ids: model.moments.map(\.id), start: moment.id))) {
                        card(moment)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 11)
                }
            }
            .padding(.bottom, 24)
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
        }
        .background(ColorToken.canvas.color.ignoresSafeArea())
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(ColorToken.canvas.color, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        // Names the way back from a moment: "Nov 11".
        .navigationTitle(Text(MemoriesView.dayDate(model.day), format: Date.FormatStyle(timeZone: .gmt).month(.abbreviated).day()))
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(MemoriesView.dayDate(model.day), format: titleFormat)
                    .textStyle(.editorTitle)
                    .foregroundStyle(ColorToken.textPrimary.color)
                    .accessibilityAddTraits(.isHeader)
            }
            ToolbarItem(placement: .topBarTrailing) { options }
        }
        .alert(Text("Hide this day from memories?", bundle: .module), isPresented: $confirmsHiding) {
            Button(role: .cancel) {} label: { Text("Cancel", bundle: .module) }
            Button { model.setHidden(true) } label: { Text("Hide day", bundle: .module) }
        } message: {
            Text("Your moments stay in the archive.", bundle: .module)
        }
        .alert(
            Text("Couldn't change what you see in memories", bundle: .module),
            isPresented: Binding(get: { model.failedVisibility != nil }, set: { if !$0 { model.dismissVisibilityFailure() } })
        ) {
            Button { model.retryVisibility() } label: { Text("Try again", bundle: .module) }
            Button(role: .cancel) { model.dismissVisibilityFailure() } label: { Text("Dismiss", bundle: .module) }
        }
        .task { await model.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in
            Task { await model.refresh() }
        }
    }

    /// BB03: the day's ••• menu. Hiding asks first; showing again is at once.
    private var options: some View {
        Menu {
            Button {
                if model.isHidden { model.setHidden(false) } else { confirmsHiding = true }
            } label: {
                Label {
                    if model.isHidden {
                        Text("Show this day in memories", bundle: .module, comment: "Day ••• (P8.3)")
                    } else {
                        Text("Hide this day from memories", bundle: .module, comment: "Day ••• (P8.3): every moment of the day, also ones added later")
                    }
                } icon: { Icon.glyphArchive.image }
            }
            .accessibilityIdentifier("day.hideFromMemories")
            if model.movieMoments >= MovieSelection.minimumMoments {
                Button {
                    let date = MemoriesView.dayDate(model.day)
                    router?.open(.newMovie(MovieSourceRule(kind: .dateRange, start: date, end: date)))
                } label: {
                    Label { Text("Make a movie of this day", bundle: .module) } icon: { Icon.glyphFilm.image }
                }
                .accessibilityIdentifier("day.movie")
            }
        } label: {
            Icon.glyphMore.image
                .resizable()
                .frame(width: 24, height: 24)
                .foregroundStyle(ColorToken.textPrimary.color)
                .frame(width: Size.minimumTapTarget, height: Size.minimumTapTarget)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(Text("Day options", bundle: .module))
        .accessibilityIdentifier("day.options")
    }

    /// "Wed, Nov 11", with the year when it isn't this one.
    private var titleFormat: Date.FormatStyle {
        let format = Date.FormatStyle(timeZone: .gmt).weekday(.abbreviated).month(.abbreviated).day()
        return model.day / 10_000 == thisYear ? format : format.year()
    }

    /// "3 moments · Yerevan".
    private var summary: some View {
        let count = Text("\(model.moments.count) moments", bundle: .module)
        let places = model.places
        return Group {
            if places.isEmpty {
                count
            } else {
                Text("Day summary: \(count) · \(places.formatted(.list(type: .and).locale(AppLanguage.shared.locale)))", bundle: .module)
            }
        }
        .textStyle(.noteMeta)
        .foregroundStyle(ColorToken.textSecondary.color)
    }

    private func card(_ moment: MomentSummary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            picture(moment)
                .padding(.horizontal, 16)
            OriginLabel(origin: moment.origin, time: time(moment.captured))
                .textStyle(.dayTime)
                .foregroundStyle(ColorToken.textSecondary.color)
                .padding(.horizontal, 18)
                .padding(.top, 8)
            if let title = moment.title {
                Text(title)
                    .textStyle(.dayCaption)
                    .foregroundStyle(ColorToken.textPrimary.color)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 18)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("day.moment")
    }

    private func picture(_ moment: MomentSummary) -> some View {
        Color(hex: 0x9C8573)
            .overlay {
                if moment.mediaType == .text {
                    PaperTileFace(excerpt: moment.excerpt, glyphSize: 20, isLarge: true)
                } else if let image = model.image(moment.picturePath) {
                    Image(uiImage: image).filling()
                }
            }
            .aspectRatio(370 / 250, contentMode: .fit)
            // Videos play here as on Memories' other tiles (Andrew, 2026-11-23); held, the card lifts in its own shape.
            .contentShape(.contextMenuPreview, DayCardBlob())
            .tileMotion(moment.id, isVideo: moment.mediaType == .video, still: model.image(moment.picturePath))
            .clipShape(DayCardBlob())
            .overlay(alignment: .topTrailing) {
                if let selfie = moment.windowPath {
                    SelfieWindow(media: model.image(selfie).map { .image(Image(uiImage: $0)) } ?? .placeholder)
                        .frame(width: 48, height: SelfieWindowStyle.height(forWidth: 48))
                        .padding(.top, 10)
                        .padding(.trailing, 19)
                }
            }
            .overlay(alignment: .bottomLeading) {
                if let duration = moment.duration {
                    VideoBadge(duration: duration)
                        .padding(.leading, 14)
                    .padding(.bottom, 10)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if moment.hasVoiceNote {
                    VoiceBadge()
                        .padding(.trailing, 19)
                        .padding(.bottom, 10)
                }
            }
            .environment(\.layoutDirection, .leftToRight)
            .accessibilityElement()
            .accessibilityLabel(pictureLabel(moment))
            .accessibilityAddTraits(.isImage)
    }

    /// "Video, voice note".
    private func pictureLabel(_ moment: MomentSummary) -> Text {
        let kind = MemoryTile.kind(moment.mediaType)
        return moment.hasVoiceNote ? kind + Text(verbatim: ", ") + Text("Description has voice note", bundle: .module) : kind
    }

    private func time(_ captured: CaptureTime) -> Text {
        var format = Date.FormatStyle(date: .omitted, time: .shortened)
        format.timeZone = captured.timeZone
        return Text(captured.instant, format: format)
    }
}
