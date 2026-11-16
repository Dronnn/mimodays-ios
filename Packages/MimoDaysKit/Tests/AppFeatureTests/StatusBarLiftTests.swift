@testable import AppFeature
import Testing

/// Top rows drawn level with the status bar's bottom, and iPhone Duo's outer display, where the status bar is on the side.
struct StatusBarLiftTests {
    @Test func underAStatusBarTheRowMovesUp() {
        #expect(StatusBarLift.topPadding(amount: 13, lifts: true, statusBarOnTop: true) == -13)
    }

    @Test func withoutAStatusBarAboveTheRowKeepsAMarginFromTheEdge() {
        #expect(StatusBarLift.topPadding(amount: 13, lifts: true, statusBarOnTop: false) == StatusBarLift.edgeMargin)
        #expect(StatusBarLift.edgeMargin > 0)
    }

    @Test func whereTheLiftIsNotDrawnNothingMoves() {
        #expect(StatusBarLift.topPadding(amount: 13, lifts: false, statusBarOnTop: true) == 0)
        #expect(StatusBarLift.topPadding(amount: 13, lifts: false, statusBarOnTop: false) == 0)
        #expect(StatusBarLift.topPadding(amount: 0, lifts: true, statusBarOnTop: false) == 0)
    }
}
