import CoreGraphics

/// U35: how far the Memory Card has turned. The whole card turns about its vertical axis in real time under the
/// finger, which drags the folded corner across the card: a full card's width is half a turn. It can be held at any
/// angle and reversed. Let go past halfway, or with a flick, and it finishes; otherwise it settles back.
/// Each flip goes on round the same way, so the back turns on to the front again.
struct MemoryCardFlip: Equatable {
    /// Degrees: 0 the front, 180 the back, 360 the front again (kept below 360 at rest).
    var angle: Double = 0

    /// Where the drag started: 0 or 180.
    var rest: Double { angle >= 180 ? 180 : 0 }

    /// The side facing the person.
    var showsBack: Bool {
        let turned = angle.truncatingRemainder(dividingBy: 360)
        return turned >= 90 && turned < 270
    }

    /// Mid-flip: neither side flat to the person.
    var isTurning: Bool { angle != 0 && angle != 180 }

    /// The angle under a finger moved `translation` along the card's width from `rest`, towards the card's middle
    /// (to the left with the corner on the right). Held between the side it started on and the next one.
    static func angle(from rest: Double, translation: CGFloat, width: CGFloat, cornerOnRight: Bool) -> Double {
        let across = cornerOnRight ? -translation : translation
        let turned = Double(across / max(width, 1)) * 180
        return rest + min(max(turned, 0), 180)
    }

    /// Where the card settles when the finger lifts at `angle`, its flick heading for `predicted`.
    static func settle(from rest: Double, angle: Double, predicted: Double) -> Double {
        angle - rest > 90 || predicted - rest > 90 ? rest + 180 : rest
    }

    /// The same side, kept below a whole turn.
    static func normalized(_ angle: Double) -> Double {
        angle >= 360 ? angle - 360 : angle
    }
}
