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
                #expect(blocks != [.trio], "a favorite or video never gets three small pieces")
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

/// U16/H.9: as many videos loop at once as Motion says (four here), the first on screen; the next takes over when one
/// leaves.
@MainActor
struct TileMotionTests {
    @Test func theFirstFourVideosOnScreenLoop() {
        let loops = TileMotion()
        loops.isOn = true
        let ids = (0..<5).map { _ in UUID() }
        for id in ids { loops.setOnScreen(id, true) }
        #expect(ids.map(loops.plays) == [true, true, true, true, false])
        loops.setOnScreen(ids[1], false)
        #expect(ids.map(loops.plays) == [true, false, true, true, true])
        loops.setOnScreen(ids[1], true)
        #expect(!loops.plays(ids[1]))
        // The screen's Motion off (or Reduce Motion, Low Power): none plays on its own.
        loops.isOn = false
        #expect(!ids.contains(where: loops.plays))
    }

    @Test func motionSettingsStartOnAndReadOlderSettings() throws {
        #expect(MotionScreen.allCases.allSatisfy { MotionSettings()[$0] })
        let old = try JSONDecoder().decode(AppearanceSettings.self, from: Data(#"{"appearance":"dark","higherContrast":false}"#.utf8))
        #expect(old.motion == MotionSettings())
        var settings = MotionSettings()
        settings[.map] = false
        #expect(!settings.map && settings.search)
        #expect(old.motion.atOnce == .automatic)
        // Fonts chosen in an earlier version are left behind; the rest of the settings still read.
        let withFonts = try JSONDecoder().decode(AppearanceSettings.self, from: Data(#"{"appearance":"dark","fonts":{"ru":{"heading":"rubik"}}}"#.utf8))
        #expect(withFonts.appearance == .dark)
    }

    /// Playing at once (Andrew, 2026-11-18): the chosen count, fewer while the iPhone is hot.
    @Test func playingAtOnceFollowsTheSettingAndTheHeat() {
        #expect(TilesAtOnce.eight.count(thermal: .nominal) == 8)
        #expect(TilesAtOnce.twelve.count(thermal: .fair) == 12)
        #expect(TilesAtOnce.all.count(thermal: .nominal) == .max)
        #expect(TilesAtOnce.all.count(thermal: .serious) == 4)
        #expect(TilesAtOnce.four.count(thermal: .critical) == 1)
        #expect([4, 8, 12].contains(TilesAtOnce.automatic.count(thermal: .nominal)))
        let loops = TileMotion()
        loops.isOn = true
        loops.limit = 8
        let ids = (0..<9).map { _ in UUID() }
        for id in ids { loops.setOnScreen(id, true) }
        #expect(ids.filter(loops.plays).count == 8 && !loops.plays(ids[8]))
    }

    @Test func aMomentShownTwiceKeepsPlayingWhileOneTileStays() {
        let loops = TileMotion()
        loops.isOn = true
        let id = UUID()
        loops.setOnScreen(id, true) // Today's hero
        loops.setOnScreen(id, true) // its tile in the month
        loops.setOnScreen(id, false)
        #expect(loops.plays(id))
        loops.setOnScreen(id, false)
        #expect(!loops.plays(id))
    }

    @Test func aTileCopyIsNamedAfterItsVideo() {
        #expect(LoopPreviews.path(for: "originals/c4/c4949e7f.mov") == "cache/loops/c4949e7f.mp4")
    }
}
