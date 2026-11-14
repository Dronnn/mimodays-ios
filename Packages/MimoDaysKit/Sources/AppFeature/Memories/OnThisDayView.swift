import Core
import DesignSystem
import Foundation
import Observation
import os
import Persistence
import SwiftData
import SwiftUI

/// One earlier year's moments on today's month and day, oldest first.
struct OnThisDayYear: Equatable, Identifiable {
    var year: Int
    var yearsAgo: Int
    var moments: [MomentSummary]

    var id: Int { year }
}

/// M14: today's month and day in every earlier year, the nearest year first.
@MainActor
@Observable
final class OnThisDayModel {
    private(set) var years: [OnThisDayYear] = []
    private(set) var isLoaded = false
    private(set) var images: [String: UIImage] = [:]
    /// yyyymmdd of today, in the device's zone.
    let today: Int

    private let library: MediaLibrary
    private let logger = Logger(subsystem: "MimoDays", category: "OnThisDay")

    init(library: MediaLibrary, clock: any DateProvider = SystemDateProvider(), calendar: Calendar = .current) {
        self.library = library
        today = LocalDay(clock.now(), in: calendar.timeZone).key
    }

    /// Every moment, in the order shown, for swiping in the viewer.
    var ids: [UUID] { years.flatMap { $0.moments.map(\.id) } }

    func refresh() async {
        let monthDay = today % 10_000
        let year = today / 10_000
        let keys = (1...100).map { (year - $0) * 10_000 + monthDay }
        let descriptor = FetchDescriptor<Moment>(
            predicate: #Predicate { $0.deletedAt == nil && keys.contains($0.localDay) },
            sortBy: [SortDescriptor(\.localDay, order: .reverse), SortDescriptor(\.capturedAt)]
        )
        do {
            let moments = try library.context.fetch(descriptor)
            years = Dictionary(grouping: moments) { $0.localDay / 10_000 }
                .map { OnThisDayYear(year: $0.key, yearsAgo: year - $0.key, moments: $0.value.map(MomentSummary.init)) }
                .sorted { $0.year > $1.year }
        } catch {
            logger.error("Reading On this day failed: \(error.localizedDescription, privacy: .public)")
        }
        isLoaded = true
        for moment in years.flatMap(\.moments) {
            await load(moment.mainPath, DayModel.photoPixels)
            await load(moment.selfiePath, DayModel.selfiePixels)
        }
    }

    func image(_ path: String?) -> UIImage? {
        path.flatMap { images[$0] }
    }

    private func load(_ path: String?, _ size: Int) async {
        guard let path, images[path] == nil, let url = try? library.store.url(for: path),
              let image = try? await library.thumbnails.thumbnail(for: url, maxPixelSize: size) else { return }
        images[path] = UIImage(cgImage: image)
    }
}

struct OnThisDayScreen: View {
    @Environment(\.mediaLibrary) private var library
    var body: some View {
        if let library { OnThisDayHost(model: OnThisDayModel(library: library)) }
    }
}

private struct OnThisDayHost: View {
    @State var model: OnThisDayModel
    var body: some View { OnThisDayView(model: model) }
}

/// M14: the title with its star, "November 11 in earlier years", then each year's moments as cards with captions.
/// "Make a movie of these" starts the wizard with every moment shown.
struct OnThisDayView: View {
    let model: OnThisDayModel
    @Environment(AppRouter.self) private var router

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("On this day", bundle: .module)
                    .textStyle(.screenTitle)
                    .foregroundStyle(ColorToken.textPrimary.color)
                    .fixedSize(horizontal: false, vertical: true)
                    .overlay(alignment: .topTrailing) {
                        Icon.markStarSolo.image
                            .resizable()
                            .frame(width: 28, height: 28.9)
                            .foregroundStyle(ColorToken.accentApricot.color)
                            .offset(x: 42, y: -4)
                            .accessibilityHidden(true)
                    }
                    .accessibilityAddTraits(.isHeader)
                    .padding(.horizontal, 20)
                Text("On this day subtitle: \(Text(MemoriesView.dayDate(model.today), format: Date.FormatStyle(timeZone: .gmt).month(.wide).day()))", bundle: .module)
                    .textStyle(.noteMeta)
                    .foregroundStyle(ColorToken.textSecondary.color)
                    .padding(.horizontal, 22)
                    .padding(.top, 4)
                if model.years.isEmpty, model.isLoaded {
                    empty.padding(.top, 72)
                }
                ForEach(model.years) { year in
                    yearLabel(year)
                        .textStyle(.labelCaps)
                        .foregroundStyle(ColorToken.textSecondary.color)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.horizontal, 20)
                        .padding(.top, year == model.years.first ? 18 : 30)
                    ForEach(year.moments) { moment in
                        NavigationLink(value: MemoriesRoute.moment(MomentPager(ids: model.ids, start: moment.id))) {
                            card(moment)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 8)
                    }
                }
                if !model.years.isEmpty {
                    Button { router.open(.newMovie(MovieSourceRule(kind: .onThisDay, momentIDs: model.ids))) } label: {
                        Text("Make a movie of these", bundle: .module)
                    }
                    .buttonStyle(SoftButtonStyle())
                    .padding(.horizontal, 20)
                    .padding(.top, 32)
                    .accessibilityIdentifier("onThisDay.movie")
                }
            }
            .padding(.bottom, 24)
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
        }
        .background(ColorToken.canvas.color.ignoresSafeArea())
        .navigationTitle(Text("On this day", bundle: .module))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(removing: .title)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task { await model.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in Task { await model.refresh() } }
    }

    /// "1 YEAR AGO · 2025".
    private func yearLabel(_ year: OnThisDayYear) -> Text {
        Text("Years ago and year: \(Text("\(year.yearsAgo) years back", bundle: .module)) · \(Text(verbatim: String(year.year)))", bundle: .module)
    }

    private func card(_ moment: MomentSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Color(hex: 0x9C8573)
                .overlay {
                    if let image = model.image(moment.mainPath) { Image(uiImage: image).filling() }
                }
                .aspectRatio(370 / 210, contentMode: .fit)
                .clipShape(DayCardBlob())
                .overlay(alignment: .topTrailing) {
                    if let selfie = moment.selfiePath {
                        SelfieWindow(media: model.image(selfie).map { .image(Image(uiImage: $0)) } ?? .placeholder)
                            .frame(width: 48, height: SelfieWindowStyle.height(forWidth: 48))
                            .padding(.top, 10)
                            .padding(.trailing, 19)
                    }
                }
                .environment(\.layoutDirection, .leftToRight)
                .accessibilityElement()
                .accessibilityLabel(moment.mediaType == .video ? Text("Video", bundle: .module) : Text("Photo", bundle: .module))
                .accessibilityAddTraits(.isImage)
                .padding(.horizontal, 16)
            if let caption = moment.title ?? moment.place {
                Text(caption)
                    .textStyle(.dayCaption)
                    .foregroundStyle(ColorToken.textPrimary.color)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 18)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("onThisDay.moment")
    }

    private var empty: some View {
        VStack(spacing: 0) {
            ExplainerArt(glyph: .explainerClock)
            Text("Nothing on this day yet", bundle: .module)
                .textStyle(.emptyTitle)
                .foregroundStyle(ColorToken.textPrimary.color)
                .padding(.top, 16)
                .accessibilityAddTraits(.isHeader)
            Text("Moments from today will be here next year.", bundle: .module)
                .textStyle(.body)
                .foregroundStyle(ColorToken.textBody.color)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
                .padding(.horizontal, 34)
        }
        .frame(maxWidth: .infinity)
    }
}
