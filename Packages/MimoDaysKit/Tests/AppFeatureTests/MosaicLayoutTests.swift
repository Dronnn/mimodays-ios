@testable import AppFeature
import CoreGraphics
import Foundation
import Testing

/// E.4: the Mosaic's month layout (U13, U16).
struct MosaicLayoutTests {
    private func moments(_ count: Int, large: Set<Int> = []) -> [MosaicLayout.Moment] {
        (0..<count).map { index in
            MosaicLayout.Moment(id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index + 1))!, prefersLarge: large.contains(index))
        }
    }

    @Test func theSameMomentsAlwaysGiveTheSameLayout() {
        let month = moments(23, large: [2, 9, 15])
        #expect(MosaicLayout.chapter(month, width: 402) == MosaicLayout.chapter(month, width: 402))
    }

    @Test func everyMomentGetsOnePieceInOrderOfItsBlock() {
        for count in 0...40 {
            let month = moments(count, large: [1, 7])
            let chapter = MosaicLayout.chapter(month, width: 402)
            #expect(Set(chapter.tiles.map(\.id)) == Set(month.map(\.id)))
            #expect(chapter.tiles.count == count)
            #expect(MosaicLayout.blocks(month).map(\.count).reduce(0, +) == count)
        }
    }

    @Test func onlyAMonthOfOneHasASinglePiece() {
        #expect(MosaicLayout.blocks(moments(1)) == [.single])
        for count in 2...40 {
            #expect(!MosaicLayout.blocks(moments(count, large: [0, 3, 8])).contains(.single), "\(count) moments")
        }
        #expect(MosaicLayout.blocks(moments(2)).count == 1)
        if case .wide = MosaicLayout.blocks(moments(2))[0] {} else { Issue.record("two moments are a wide and a tall piece") }
    }

    @Test func aFavoriteOrVideoTakesItsBlocksLargerPiece() {
        // One block per month of two or three; across many months the large moment, last in time, has the
        // biggest piece whenever the block has a bigger one.
        for base in 0..<40 {
            for count in 2...3 {
                let month = (0..<count).map { index in
                    MosaicLayout.Moment(
                        id: UUID(uuidString: String(format: "%08d-0000-0000-0000-%012d", base, index + 1))!, prefersLarge: index == count - 1
                    )
                }
                let blocks = MosaicLayout.blocks(month)
                #expect(blocks.count == 1)
                guard blocks != [.trio] else { continue }
                let tiles = MosaicLayout.chapter(month, width: 402).tiles
                let area = { (tile: MosaicLayout.Tile) in tile.frame.width * tile.frame.height }
                #expect(tiles.max { area($0) < area($1) }?.id == month[count - 1].id)
            }
        }
    }

    @Test func piecesStayOnScreenTiltGentlyAndDoNotOverlap() {
        let month = moments(30, large: [0, 4, 11, 20])
        let chapter = MosaicLayout.chapter(month, width: 402)
        for tile in chapter.tiles {
            #expect(tile.frame.minX >= MosaicLayout.margin && tile.frame.maxX <= 402 - MosaicLayout.margin)
            #expect(abs(tile.tilt) <= MosaicLayout.maximumTilt)
            #expect(tile.frame.maxY <= chapter.height)
        }
        for (index, tile) in chapter.tiles.enumerated() {
            for other in chapter.tiles[(index + 1)...] {
                #expect(!tile.frame.intersects(other.frame), "\(tile.frame) overlaps \(other.frame)")
            }
        }
    }

    @Test func anIPadPutsBlocksSideBySideAtAboutIPhoneSize() {
        #expect(MosaicLayout.lanes(width: 402) == 1 && MosaicLayout.lanes(width: 375) == 1)
        #expect(MosaicLayout.lanes(width: 820) == 2 && MosaicLayout.lanes(width: 744) == 2)
        #expect(MosaicLayout.lanes(width: 1180) == 3 && MosaicLayout.lanes(width: 1366) == 3)
        let month = moments(30, large: [0, 4, 11, 20])
        for width in [820.0, 1180, 1366] {
            let chapter = MosaicLayout.chapter(month, width: width)
            #expect(chapter.tiles.count == 30)
            #expect(chapter.tiles.allSatisfy { $0.frame.minX >= MosaicLayout.margin && $0.frame.maxX <= width - MosaicLayout.margin })
            #expect(chapter.tiles.map(\.frame.width).max()! < 300, "pieces stay about iPhone size")
            for (index, tile) in chapter.tiles.enumerated() {
                #expect(chapter.tiles[(index + 1)...].allSatisfy { !$0.frame.intersects(tile.frame) })
            }
            #expect(chapter.height < MosaicLayout.chapter(month, width: 402).height)
        }
    }

    @Test func aFeatureBlockMatchesTheDesign() {
        // U13 on a 402 pt screen: the big piece about 2 of 3 columns, the small ones a column each.
        let (cells, height) = MosaicLayout.cells(.feature(mirrored: false), unit: (402 - 24 - 16) / 3)
        #expect(abs(cells[0].width - 249.33) < 0.1 && cells[1].minX > cells[0].maxX)
        #expect(abs(height - cells[0].height) < 0.01)
        let (mirrored, _) = MosaicLayout.cells(.feature(mirrored: true), unit: (402 - 24 - 16) / 3)
        #expect(mirrored[0].maxX > mirrored[1].maxX && mirrored[1].minX == 0)
    }
}
