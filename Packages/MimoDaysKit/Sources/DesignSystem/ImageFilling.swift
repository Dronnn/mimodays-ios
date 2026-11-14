import SwiftUI

public extension Image {
    /// Fills its frame, cropped by whatever clips it. Clipping only hides the cropped part: it still lies past the
    /// frame and would take taps meant for what it overlaps (Make my movie opened On this day), so it takes none.
    func filling() -> some View {
        resizable().scaledToFill().allowsHitTesting(false)
    }
}
