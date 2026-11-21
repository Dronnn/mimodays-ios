import DesignSystem
import SwiftUI

/// P8.3 (BB02, BB05): says a moment or a day is out of memories, in text, not by color alone.
struct HiddenFromMemoriesChip: View {
    /// Hidden because its whole day is (the card back says so; showing it again is the day's choice).
    var withItsDay = false

    var body: some View {
        HStack(spacing: 5) {
            Icon.glyphArchive.image.resizable().frame(width: 15, height: 15).accessibilityHidden(true)
            Group {
                if withItsDay {
                    Text("Hidden with this day", bundle: .module, comment: "Memory Card back: the moment's day is hidden from memories (P8.3)")
                } else {
                    Text("Hidden from memories", bundle: .module, comment: "Memory Card back and day: out of On this day, widgets and automatic movies (P8.3)")
                }
            }
            .textStyle(.meta)
            .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(ColorToken.textPrimary.color)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Capsule().fill(ColorToken.surfaceChip.color))
        .accessibilityElement(children: .combine)
    }
}
