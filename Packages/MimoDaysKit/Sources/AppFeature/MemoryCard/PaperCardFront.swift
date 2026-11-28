import Core
import DesignSystem
import SwiftUI

/// P8.11 II04: a written moment's front. Paper in the card's outline: the caption in coral, the words in the
/// hand-written face as far as they fit, the day, time and place at the bottom; the corner turns it to the whole text.
struct PaperCardFront: View {
    let moment: ViewerMoment
    let size: CGSize
    let cornerOnRight: Bool
    let actions: MemoryCardActions

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title = moment.title {
                Text(title)
                    .textStyle(.viewerPlace)
                    .foregroundStyle(ColorToken.textLink.color)
                    .lineLimit(2)
                    .padding(.trailing, 30)
            }
            Text(moment.note ?? "")
                .textStyle(.paperExcerpt)
                .foregroundStyle(ColorToken.textPrimary.color)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                // As much as fits, then "…"; the back has it all.
                .truncationMode(.tail)
            footer
                .textStyle(.viewerMeta)
                .foregroundStyle(ColorToken.textSecondary.color)
                .lineLimit(2)
                .padding(.trailing, 40)
        }
        .padding(.horizontal, 22)
        .padding(.top, 26)
        .padding(.bottom, 30)
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .background(ColorToken.surfaceCard.color)
        .overlay(alignment: .topTrailing) {
            Icon.markStarSolo.image
                .resizable()
                .frame(width: 20, height: 20.6)
                .foregroundStyle(ColorToken.actionCoral.color)
                .padding(.top, 22)
                .padding(.trailing, 22)
                .accessibilityHidden(true)
        }
        .overlay(alignment: .bottomTrailing) {
            MemoryCardFlipCorner()
                .scaleEffect(x: cornerOnRight ? 1 : -1)
                .padding(.trailing, 7)
                .padding(.bottom, 10)
        }
        .clipShape(MemoryCardOutline())
        .overlay { MemoryCardOutline().strokeBorder(ColorToken.borderSubtle.color, lineWidth: 3).allowsHitTesting(false) }
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: Text("Read moment", bundle: .module), actions.flip)
        // Only where there is one, as on the photo and video cards.
        .accessibilityActions {
            if actions.canStep(1) {
                Button { actions.step(1) } label: { Text("Next moment", bundle: .module) }
            }
            if actions.canStep(-1) {
                Button { actions.step(-1) } label: { Text("Previous moment", bundle: .module) }
            }
        }
        .accessibilityIdentifier("card.readMoment")
    }

    /// "Sat, Nov 21 · 2:37 PM · Yerevan", in the moment's own time zone.
    private var footer: Text {
        var day = Date.FormatStyle().weekday(.abbreviated).month(.abbreviated).day()
        day.timeZone = moment.captured.timeZone
        var time = Date.FormatStyle(date: .omitted, time: .shortened)
        time.timeZone = moment.captured.timeZone
        let when = Text("\(Text(moment.captured.instant, format: day)) · \(Text(moment.captured.instant, format: time))", bundle: .module)
        guard let place = moment.place else { return when }
        return Text("\(when) · \(place)", bundle: .module)
    }
}
