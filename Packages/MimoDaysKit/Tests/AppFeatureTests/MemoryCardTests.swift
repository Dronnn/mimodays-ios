@testable import AppFeature
import CoreGraphics
import Persistence
import Testing

/// D.8: how far the card turns under the finger and where it settles (U35), and where the card and its window go
/// (U20-U24).
struct MemoryCardTests {
    // MARK: Flip

    @Test func aDragAcrossTheWholeCardIsHalfATurnTowardsTheMiddle() {
        // The fold on the right: dragging left turns it.
        #expect(MemoryCardFlip.angle(from: 0, translation: -180, width: 360, cornerOnRight: true) == 90)
        #expect(MemoryCardFlip.angle(from: 0, translation: -360, width: 360, cornerOnRight: true) == 180)
        // The fold on the left (right-to-left): dragging right turns it.
        #expect(MemoryCardFlip.angle(from: 0, translation: 90, width: 360, cornerOnRight: false) == 45)
        // From the back it goes on round the same way.
        #expect(MemoryCardFlip.angle(from: 180, translation: -180, width: 360, cornerOnRight: true) == 270)
    }

    @Test func aDragIsHeldBetweenTheSideItStartedOnAndTheNext() {
        #expect(MemoryCardFlip.angle(from: 0, translation: 50, width: 360, cornerOnRight: true) == 0)
        #expect(MemoryCardFlip.angle(from: 0, translation: -900, width: 360, cornerOnRight: true) == 180)
        #expect(MemoryCardFlip.angle(from: 180, translation: -900, width: 360, cornerOnRight: true) == 360)
    }

    @Test func itFinishesPastHalfwayOrWithAFlickAndOtherwiseSettlesBack() {
        #expect(MemoryCardFlip.settle(from: 0, angle: 100, predicted: 100) == 180)
        #expect(MemoryCardFlip.settle(from: 0, angle: 40, predicted: 150) == 180)
        #expect(MemoryCardFlip.settle(from: 0, angle: 80, predicted: 80) == 0)
        #expect(MemoryCardFlip.settle(from: 180, angle: 300, predicted: 300) == 360)
        #expect(MemoryCardFlip.settle(from: 180, angle: 200, predicted: 220) == 180)
    }

    @Test func theSidesChangeOverAtNinetyDegrees() {
        #expect(!MemoryCardFlip(angle: 0).showsBack)
        #expect(!MemoryCardFlip(angle: 89).showsBack)
        #expect(MemoryCardFlip(angle: 90).showsBack)
        #expect(MemoryCardFlip(angle: 180).showsBack)
        #expect(!MemoryCardFlip(angle: 270).showsBack)
        #expect(!MemoryCardFlip(angle: 360).showsBack)
        #expect(MemoryCardFlip(angle: 180).rest == 180 && MemoryCardFlip(angle: 120).rest == 0)
        #expect(MemoryCardFlip(angle: 45).isTurning && !MemoryCardFlip(angle: 180).isTurning)
        #expect(MemoryCardFlip.normalized(360) == 0 && MemoryCardFlip.normalized(180) == 180)
    }

    // MARK: Geometry

    @Test func theCardTakesTheMomentsShapeAsLargeAsItsSlotAllows() {
        let slot = CGSize(width: 359, height: 562)
        let tall = MemoryCardGeometry.card(aspectRatio: 9 / 16, in: slot)
        #expect(abs(tall.height - 562) < 0.01 && abs(tall.width - 562 * 9 / 16) < 0.01)
        #expect(MemoryCardGeometry.card(aspectRatio: 1, in: slot) == CGSize(width: 359, height: 359))
        let wide = MemoryCardGeometry.card(aspectRatio: 16 / 9, in: slot)
        #expect(wide.width == 359 && abs(wide.height - 359 * 9 / 16) < 0.01)
        #expect(MemoryCardGeometry.card(aspectRatio: 1, in: .zero) == .zero)
    }

    @Test func theSlotLeavesMarginsAndStaysACardOnWideScreens() {
        #expect(MemoryCardGeometry.slotWidth(screen: 402) == 359)
        #expect(MemoryCardGeometry.slotWidth(screen: 1366) == MemoryCardGeometry.maximumSlotWidth)
        #expect(MemoryCardGeometry.slotWidth(screen: 20) == 0)
    }

    @Test func theWindowKeepsItsShareOfTheCardAtAnySize() {
        let layout = MemoryCardGeometry.windowLayout(format: .portrait, screenWidth: 402, topInset: 62)
        let placement = CameraSettings.SelfieWindow(corner: .bottomLeft, scale: .large)
        let full = MemoryCardGeometry.windowFrame(placement, layout: layout, card: layout.preview)
        let half = MemoryCardGeometry.windowFrame(placement, layout: layout, card: CGSize(width: layout.preview.width / 2, height: layout.preview.height / 2))
        #expect(full == layout.windowFrame(placement).frame)
        #expect(abs(half.width - full.width / 2) < 0.01 && abs(half.minX - full.minX / 2) < 0.01 && abs(half.minY - full.minY / 2) < 0.01)
    }
}
