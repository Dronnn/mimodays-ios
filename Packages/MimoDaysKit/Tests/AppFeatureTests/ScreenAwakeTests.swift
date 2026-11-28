@testable import AppFeature
import Testing

/// P8.20: the screen stays on while anything holds it, and dims again once the last lets go.
@MainActor
@Suite(.serialized)
struct ScreenAwakeTests {
    @Test func theScreenStaysOnUntilTheLastHolderLetsGo() {
        var states: [Bool] = []
        let apply = ScreenAwake.apply
        defer { ScreenAwake.apply = apply }
        ScreenAwake.apply = { states.append($0) }

        ScreenAwake.hold()
        ScreenAwake.hold()
        ScreenAwake.release()
        #expect(states == [true])
        ScreenAwake.release()
        #expect(states == [true, false])
        // An extra release can't leave the count below nothing.
        ScreenAwake.release()
        ScreenAwake.hold()
        #expect(states == [true, false, true])
        ScreenAwake.release()
        #expect(states == [true, false, true, false])
    }
}
