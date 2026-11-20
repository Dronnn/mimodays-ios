import DesignSystem
import Persistence
import SwiftUI

/// 7.6, approved by Andrew on 2026-11-13 (Penpot §H20): where a moment came from, next to its time. A surprise gets a
/// small coral star and "Surprise"; one taken on your own shows just the time; an imported one says "Imported".
struct OriginLabel: View {
    enum Order {
        /// Lists and review: "8:05 AM · Surprise".
        case timeFirst
        /// The viewer's meta line: "Surprise · Wed, Nov 11 · 6:42 PM".
        case originFirst
    }

    let origin: MomentOrigin
    let time: Text
    var order = Order.timeFirst

    var body: some View {
        switch origin {
        case .randomPrompt:
            HStack(spacing: 4) {
                Icon.markStarSmall.image
                    .resizable()
                    .frame(width: 12, height: 12)
                    .foregroundStyle(ColorToken.accentCoralMark.color)
                order == .timeFirst ? Text("\(time) · Surprise", bundle: .module) : Text("Surprise · \(time)", bundle: .module)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Surprise moment, \(time)", bundle: .module))
        case .imported:
            Text("Imported · \(time)", bundle: .module)
                .accessibilityLabel(Text("Imported from Photos, \(time)", bundle: .module))
        case .manual:
            time
        }
    }
}
