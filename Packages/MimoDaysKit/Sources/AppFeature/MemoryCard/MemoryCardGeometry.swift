import CoreGraphics
import Persistence

/// Where a Memory Card and its pieces go (U20-U24). The card takes the moment's own shape (Andrew, 2026-11-15):
/// 9:16 as tall as fits, 1:1 square, 16:9 wide, centred in the same slot. Neighbours peek 7 pt away on each side.
enum MemoryCardGeometry {
    /// The slot's margin on each side, and the gap between neighbouring cards: 359 pt of a 402 pt screen.
    static let sideMargin: CGFloat = 21.5
    static let pageGap: CGFloat = 7
    /// Wide screens keep the card a card.
    static let maximumSlotWidth: CGFloat = 620
    /// Under the card: the voice pill 18 pt below it. No button row: the window swaps, the corner flips (Andrew,
    /// 2026-11-15), and the card takes the room.
    static let pillGap: CGFloat = 18
    static let pillHeight: CGFloat = 52
    /// What every page keeps under its slot, voice note or not, so cards don't jump between pages.
    static var belowCard: CGFloat { pillGap + pillHeight }
    /// The space over the card under the bar (U20: the bar ends at 98, the card starts at 108).
    static let topGap: CGFloat = 10

    static func slotWidth(screen: CGFloat) -> CGFloat {
        min(max(screen - 2 * sideMargin, 0), maximumSlotWidth)
    }

    /// The card's slot on a page of `size`.
    static func slot(page size: CGSize) -> CGSize {
        CGSize(width: size.width, height: max(size.height - topGap - belowCard, 0))
    }

    /// The card in its slot: `aspectRatio` (width over height) as large as fits.
    static func card(aspectRatio: CGFloat, in slot: CGSize) -> CGSize {
        guard aspectRatio > 0, slot.width > 0, slot.height > 0 else { return .zero }
        let width = min(slot.width, slot.height * aspectRatio)
        return CGSize(width: width, height: width / aspectRatio)
    }

    /// The selfie window's layout on a card: the camera's for the format at the screen's width (as review lays
    /// it out), drawn scaled to the card. What is saved does not depend on the card's size.
    static func windowLayout(format: CaptureFormat, screenWidth: CGFloat, topInset: CGFloat) -> SelfieWindowLayout {
        SelfieWindowLayout.media(width: screenWidth, format: format, topInset: topInset)
    }

    /// The window's frame on a card of `card` size, for `placement` in `layout`.
    static func windowFrame(_ placement: CameraSettings.SelfieWindow, layout: SelfieWindowLayout, card: CGSize) -> CGRect {
        let scale = layout.preview.width > 0 ? card.width / layout.preview.width : 1
        let frame = layout.windowFrame(placement).frame
        return CGRect(x: frame.minX * scale, y: frame.minY * scale, width: frame.width * scale, height: frame.height * scale)
    }
}
