import CoreGraphics
import Foundation

/// U13, U16: one month of the Mosaic laid out in pieces on three columns. Blocks of a big piece beside two small ones,
/// three small ones, or a wide piece beside a tall one follow each other down the month; favorites and videos get
/// the larger pieces. Every piece is a little smaller than its cell by an uneven amount and tilts up to 3°.
/// The same moments always give the same layout: the choices come from the moments' ids, not from chance.
/// A wide screen keeps the pieces at about the iPhone's size and puts blocks side by side in lanes (Andrew,
/// 2026-11-15): two on iPad portrait, three in landscape, each block going to the lane that ends highest.
enum MosaicLayout {
    /// What the layout needs of a moment.
    struct Moment: Equatable {
        let id: UUID
        /// A favorite or a video: it takes the block's larger piece.
        let prefersLarge: Bool
    }

    struct Tile: Equatable {
        let id: UUID
        /// In the month's own space: x from the screen's leading edge, y from the month's first block.
        let frame: CGRect
        /// Degrees, -3...3.
        let tilt: Double
    }

    struct Chapter: Equatable {
        let tiles: [Tile]
        let height: CGFloat
    }

    static let margin: CGFloat = 12
    static let gap: CGFloat = 8
    /// Between blocks.
    static let blockGap: CGFloat = 10
    static let maximumTilt = 3.0
    /// The narrowest lane: one on any iPhone, two from about 700 pt.
    static let minimumLaneWidth: CGFloat = 340

    /// Lanes that fit across `width`.
    static func lanes(width: CGFloat) -> Int {
        max(1, Int((width - 2 * margin + gap) / (minimumLaneWidth + gap)))
    }

    enum Block: Equatable {
        /// A big square piece and two small ones stacked beside it; mirrored puts the big one on the right.
        case feature(mirrored: Bool)
        /// Three small pieces in a row.
        case trio
        /// A wide piece and a tall one beside it.
        case wide(mirrored: Bool)
        /// A month's only moment.
        case single

        var count: Int {
            switch self {
            case .feature, .trio: 3
            case .wide: 2
            case .single: 1
            }
        }
    }

    /// The blocks for `moments` (newest first), in order.
    static func blocks(_ moments: [Moment]) -> [Block] {
        guard let first = moments.first else { return [] }
        var random = SeededRandom(first.id)
        var blocks: [Block] = []
        var index = 0
        while index < moments.count {
            let rest = moments.count - index
            let next = moments[index..<min(index + 3, moments.count)]
            let roll = random.next() % 100
            let mirrored = random.next() % 2 == 1
            let block: Block
            // No choice leaves a moment on its own: only a month of one ends with a single piece.
            if rest == 1 {
                block = .single
            } else if rest == 2 || rest == 4 {
                block = .wide(mirrored: mirrored)
            } else {
                let hasLarge = next.contains(where: \.prefersLarge)
                let followsFeature = if case .feature = blocks.last { true } else { false }
                if hasLarge {
                    // A favorite or a video always gets a larger piece: never three small ones.
                    block = rest > 3 && followsFeature || rest > 3 && roll >= 70 ? .wide(mirrored: mirrored) : .feature(mirrored: mirrored)
                } else {
                    block = !followsFeature && roll < 35 ? .feature(mirrored: mirrored) : .trio
                }
            }
            blocks.append(block)
            index += block.count
        }
        return blocks
    }

    /// The month laid out across `width` points.
    static func chapter(_ moments: [Moment], width: CGFloat) -> Chapter {
        let count = lanes(width: width)
        let lane = max(0, (width - 2 * margin - CGFloat(count - 1) * gap) / CGFloat(count))
        let unit = max(0, (lane - 2 * gap) / 3)
        var tiles: [Tile] = []
        var tops = [CGFloat](repeating: 0, count: count)
        var index = 0
        for block in blocks(moments) {
            // The lane that ends highest, the leading one on a tie.
            let column = tops.indices.min { tops[$0] < tops[$1] } ?? 0
            let left = margin + CGFloat(column) * (lane + gap)
            var members = Array(moments[index..<index + block.count])
            index += block.count
            // The larger piece is the block's first cell: the first favorite or video moves there.
            if let large = members.firstIndex(where: \.prefersLarge), large > 0 {
                members.insert(members.remove(at: large), at: 0)
            }
            let (cells, height) = cells(block, unit: unit)
            for (member, cell) in zip(members, cells) {
                tiles.append(tile(member.id, in: cell.offsetBy(dx: left, dy: tops[column])))
            }
            tops[column] += height + blockGap
        }
        return Chapter(tiles: tiles, height: max(0, (tops.max() ?? 0) - blockGap))
    }

    /// The block's cells, larger piece first, and its height.
    static func cells(_ block: Block, unit u: CGFloat) -> ([CGRect], CGFloat) {
        let double = 2 * u + gap
        let third = 2 * (u + gap)
        switch block {
        case let .feature(mirrored):
            let big = CGRect(x: mirrored ? u + gap : 0, y: 0, width: double, height: double)
            let column: CGFloat = mirrored ? 0 : third
            return ([big, CGRect(x: column, y: 0, width: u, height: u), CGRect(x: column, y: u + gap, width: u, height: u)], double)
        case .trio:
            let height = (u * 0.92).rounded()
            return ((0..<3).map { CGRect(x: CGFloat($0) * (u + gap), y: 0, width: u, height: height) }, height)
        case let .wide(mirrored):
            let height = (u * 1.3).rounded()
            return ([
                CGRect(x: mirrored ? u + gap : 0, y: 0, width: double, height: height),
                CGRect(x: mirrored ? 0 : third, y: 0, width: u, height: height),
            ], height)
        case .single:
            let height = (u * 1.3).rounded()
            return ([CGRect(x: 0, y: 0, width: double, height: height)], height)
        }
    }

    /// The piece in its cell: in from each edge by 1-7 pt and tilted, both from its own id.
    private static func tile(_ id: UUID, in cell: CGRect) -> Tile {
        var random = SeededRandom(id)
        let insets = (0..<4).map { _ in CGFloat(1 + random.next() % 7) }
        let frame = CGRect(
            x: cell.minX + insets[0], y: cell.minY + insets[1],
            width: max(0, cell.width - insets[0] - insets[2]), height: max(0, cell.height - insets[1] - insets[3])
        )
        let tilt = (Double(random.next() % 601) / 100 - 3).clamped(to: -maximumTilt...maximumTilt)
        return Tile(id: id, frame: frame, tilt: tilt)
    }
}

/// SplitMix64 from a UUID's bytes: the same id gives the same numbers on every run and device.
struct SeededRandom {
    private var state: UInt64

    init(_ id: UUID) {
        let bytes = id.uuid
        let high = [bytes.0, bytes.1, bytes.2, bytes.3, bytes.4, bytes.5, bytes.6, bytes.7].reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
        let low = [bytes.8, bytes.9, bytes.10, bytes.11, bytes.12, bytes.13, bytes.14, bytes.15].reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
        state = high ^ (low &* 0x9E37_79B9_7F4A_7C15)
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double { Swift.min(Swift.max(self, range.lowerBound), range.upperBound) }
}
