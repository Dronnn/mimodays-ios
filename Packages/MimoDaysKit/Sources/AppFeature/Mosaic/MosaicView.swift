import Core
import DesignSystem
import SwiftData
import SwiftUI

/// U13-U15: the home's other side. Every moment as a piece of a mosaic, month by month, newest first; favorites and
/// videos take the larger pieces. A piece opens its Memory Card. Under ten moments a note says it grows (U14).
struct MosaicView: View {
    /// Its own tiles source, newest first whatever Memories is set to.
    let model: MemoriesModel
    @State private var width: CGFloat = 0
    @Environment(\.horizontalSizeClass) private var sizeClass

    /// A month: yyyymm and its moments, newest first.
    struct Month: Identifiable, Equatable {
        let id: Int
        let items: [MemoryItem]
    }

    /// U14's note shows for the first nine moments (Andrew, 2026-11-15).
    static let growingUntil = 10

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HomeHeader()
                title
                    .padding(.top, 13)
                    .padding(.horizontal, 24)
                ForEach(months) { month in
                    chapter(month)
                        .padding(.top, 19)
                }
                if model.isLoaded, model.allIDs.count < Self.growingUntil {
                    growingNote
                        .padding(.top, 56)
                        .padding(.horizontal, 20)
                }
            }
            // On iPhone the wordmark sits up level with the status bar's bottom, as on Today.
            .padding(.top, sizeClass == .compact ? -13 : 0)
            .padding(.bottom, 72)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { width = $0 }
        .scrollBounceBehavior(.basedOnSize)
        .background(ColorToken.canvas.color.ignoresSafeArea())
        .task { model.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in model.refresh() }
        .accessibilityIdentifier("mosaic")
    }

    /// Month rows with their moments, newest first.
    var months: [Month] {
        var months: [Month] = []
        for row in model.rows {
            switch row {
            case let .month(key, _): months.append(Month(id: key, items: []))
            case let .day(_, items):
                guard let last = months.popLast() else { continue }
                months.append(Month(id: last.id, items: last.items + items))
            }
        }
        return months
    }

    // MARK: Pieces

    /// "Your mosaic", and how many moments since when.
    private var title: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Your mosaic", bundle: .module)
                .textStyle(.mosaicTitle)
                .foregroundStyle(ColorToken.textPrimary.color)
                .accessibilityAddTraits(.isHeader)
            if model.isLoaded {
                count
                    .textStyle(.noteMeta)
                    .foregroundStyle(ColorToken.textSecondary.color)
            }
        }
    }

    private var count: Text {
        let count = model.allIDs.count
        guard count >= Self.growingUntil, let first = months.last else {
            return Text("\(count) moments so far", bundle: .module)
        }
        return Text("\(count) moments since \(Self.monthName(first.id, now: model.now))", bundle: .module)
    }

    /// "November", or "November 2025" from another year.
    static func monthName(_ key: Int, now: Date) -> String {
        let year = key / 100
        var components = DateComponents(year: year, month: key % 100, day: 1)
        components.calendar = Calendar.current
        guard let date = components.date else { return "" }
        let thisYear = Calendar.current.component(.year, from: now) == year
        return date.formatted(thisYear ? .dateTime.month(.wide) : .dateTime.month(.wide).year())
    }

    private func chapter(_ month: Month) -> some View {
        let layout = MosaicLayout.chapter(
            month.items.map { MosaicLayout.Moment(id: $0.id, prefersLarge: $0.isFavorite || $0.mediaType == .video) },
            width: width
        )
        let items = Dictionary(uniqueKeysWithValues: month.items.map { ($0.id, $0) })
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text(Self.monthName(month.id, now: model.now))
                    .textStyle(.mosaicChapter)
                    .foregroundStyle(ColorToken.textPrimary.color)
                    .accessibilityAddTraits(.isHeader)
                Icon.markBrush.image
                    .resizable()
                    .frame(width: 196.3, height: 12.9)
                    .foregroundStyle(ColorToken.actionCoral.color)
                    .padding(.leading, -2)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 26)
            ZStack(alignment: .topLeading) {
                ForEach(layout.tiles, id: \.id) { tile in
                    if let item = items[tile.id] {
                        piece(item, tile)
                    }
                }
            }
            .frame(width: width, height: layout.height, alignment: .topLeading)
            // The layout counts from the left edge; a mosaic reads the same either way.
            .environment(\.layoutDirection, .leftToRight)
            .padding(.top, 2)
        }
    }

    private func piece(_ item: MemoryItem, _ tile: MosaicLayout.Tile) -> some View {
        NavigationLink(value: MemoriesRoute.moment(MomentPager(ids: model.allIDs, start: item.id, origin: .mosaic))) {
            MosaicPiece(item: item, detail: model.details[item.id], image: model.images[item.id])
                .frame(width: tile.frame.width, height: tile.frame.height)
        }
        .buttonStyle(.plain)
        .rotationEffect(.degrees(tile.tilt))
        .offset(x: tile.frame.minX, y: tile.frame.minY)
        .task { await model.load(item.id) }
        .accessibilityIdentifier("mosaic.piece")
    }

    /// U14: "Your mosaic grows with every moment".
    private var growingNote: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your mosaic grows with every moment", bundle: .module)
                .textStyle(.mosaicNoteTitle)
                .foregroundStyle(ColorToken.textPrimary.color)
            Text("Each one finds its place here, month by month. Tap any piece to open it.", bundle: .module)
                .textStyle(.pageIntro)
                .foregroundStyle(ColorToken.textBody.color)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(ColorToken.surfaceCard.color))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("mosaic.growing")
    }
}

/// `Mosaic / Photo`, `Mosaic / Video`: the composed thumbnail in a hand-cut cream frame with a soft shadow; a video's
/// length on a loop chip, a heart for a favorite.
struct MosaicPiece: View {
    let item: MemoryItem
    let detail: TileDetail?
    let image: UIImage?

    var body: some View {
        Color(hex: 0xC9B8AA)
            .overlay {
                if let image { Image(uiImage: image).filling() }
            }
            .clipShape(MemoryCardOutline())
            .overlay { MemoryCardOutline().strokeBorder(ColorToken.mediaFrame.color, lineWidth: 4) }
            .background {
                MemoryCardOutline()
                    .fill(ColorToken.mediaFrame.color)
                    .shadow(color: ColorToken.textPrimary.color.opacity(0.14), radius: 4, y: 3)
            }
            .overlay(alignment: .bottomLeading) {
                if let duration = detail?.duration {
                    VideoBadge(duration: duration)
                        .padding(10)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if item.isFavorite {
                    HeartShape()
                        .fill(ColorToken.actionCoral.color)
                        .frame(width: 16, height: 14)
                        .padding(12)
                }
            }
            .contentShape(MemoryCardOutline())
            .accessibilityElement()
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isButton)
    }

    private var label: Text {
        let time = Text(item.captured.instant, format: .dateTime.month(.wide).day().hour().minute())
        let kind = item.mediaType == .video ? Text("Video", bundle: .module) : Text("Photo", bundle: .module)
        return item.isFavorite
            ? Text("\(kind) from \(time), favorite", bundle: .module)
            : Text("\(kind) from \(time)", bundle: .module)
    }
}
