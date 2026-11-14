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
        do {
            moments = try context.fetch(descriptor).map(MomentSummary.init)
        } catch {
            logger.error("Reading the day failed: \(error.localizedDescription, privacy: .public)")
        }
        for moment in moments {
            await load(moment.mainPath, Self.photoPixels)
            await load(moment.selfiePath, Self.selfiePixels)
        }
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
            DayHost(model: DayModel(day: day, library: library), thisYear: thisYear)
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

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                summary
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                ForEach(model.moments) { moment in
                    NavigationLink(value: MemoriesRoute.moment(MomentPager(ids: model.moments.map(\.id), start: moment.id))) {
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
        }
        .task { await model.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in
            Task { await model.refresh() }
        }
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
                Text("Day summary: \(count) · \(places.formatted(.list(type: .and)))", bundle: .module)
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
                if let image = model.image(moment.mainPath) { Image(uiImage: image).resizable().scaledToFill() }
            }
            .aspectRatio(370 / 250, contentMode: .fit)
            .clipShape(DayCardBlob())
            .overlay(alignment: .topTrailing) {
                if let selfie = moment.selfiePath {
                    SelfieWindow(media: model.image(selfie).map { .image(Image(uiImage: $0)) } ?? .placeholder)
                        .frame(width: 48, height: SelfieWindowStyle.height(forWidth: 48))
                        .padding(.top, 10)
                        .padding(.trailing, 19)
                }
            }
            .overlay(alignment: .bottomLeading) {
                if let duration = moment.duration {
                    HStack(spacing: 4) {
                        Icon.glyphPlay.image.resizable().frame(width: 7.2, height: 8.8)
                        Text(Duration.seconds(duration.rounded()), format: .time(pattern: .minuteSecond))
                            .textStyle(.tileBadge)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9)
                    .frame(height: 22)
                    .background(Capsule().fill(ColorToken.mediaScrim.color))
                    .padding(.leading, 14)
                    .padding(.bottom, 10)
                }
            }
            .environment(\.layoutDirection, .leftToRight)
            .accessibilityElement()
            .accessibilityLabel(moment.mediaType == .video ? Text("Video", bundle: .module) : Text("Photo", bundle: .module))
            .accessibilityAddTraits(.isImage)
    }

    private func time(_ captured: CaptureTime) -> Text {
        var format = Date.FormatStyle(date: .omitted, time: .shortened)
        format.timeZone = captured.timeZone
        return Text(captured.instant, format: format)
    }
}
