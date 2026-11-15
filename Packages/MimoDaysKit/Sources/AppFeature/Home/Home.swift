import Foundation
import Observation
import SwiftUI

/// The two sides of the first tab (U10-U16): Today and the Mosaic.
enum HomeSide: String, Codable, Sendable {
    case today
    case mosaic
}

/// This iPhone's home: the side last shown and whether the first-time flip hint has been shown (U11, U16).
struct HomeSettings: Codable, Equatable, Sendable {
    var side = HomeSide.today
    var showedFlipHint = false
}

typealias HomePreferences = DevicePreference<HomeSettings>

extension DevicePreference<HomeSettings> {
    static func home(_ defaults: UserDefaults?) -> HomePreferences {
        HomePreferences(key: "homeSettings", defaults: defaults, initial: HomeSettings())
    }
}

/// U16: the whole screen turns like a two-sided card between Today and the Mosaic, from the header's switch, a drag
/// on the page corner or across the header. It follows the finger, can be held and reversed, finishes past 90° or
/// with a flick and otherwise settles back; each turn goes on round the same way.
@MainActor
@Observable
final class HomeTurn {
    private(set) var flip: MemoryCardFlip
    /// Where a drag started, while it lasts.
    @ObservationIgnored private var dragRest: Double?
    @ObservationIgnored private let preferences: HomePreferences?

    init(preferences: HomePreferences?) {
        self.preferences = preferences
        flip = MemoryCardFlip(angle: preferences?.value.side == .mosaic ? 180 : 0)
    }

    /// The side facing the person: it changes over at 90° of a turn.
    var side: HomeSide { flip.showsBack ? .mosaic : .today }

    /// The side the turn is heading for, or resting on.
    var target: HomeSide { MemoryCardFlip(angle: flip.rest).showsBack ? .mosaic : .today }

    /// The header's switch, or the corner tapped.
    func show(_ side: HomeSide, reduceMotion: Bool) {
        guard side != target else { return }
        settle(at: flip.rest + 180, reduceMotion: reduceMotion)
    }

    func toggle(reduceMotion: Bool) {
        show(target == .today ? .mosaic : .today, reduceMotion: reduceMotion)
    }

    /// The finger `translation` points along a page `width` from where it went down; the corner is trailing.
    func drag(_ translation: CGFloat, width: CGFloat, cornerOnRight: Bool, reduceMotion: Bool) {
        let rest = dragRest ?? flip.rest
        dragRest = rest
        guard !reduceMotion else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            flip.angle = MemoryCardFlip.angle(from: rest, translation: translation, width: width, cornerOnRight: cornerOnRight)
        }
    }

    /// Let go: past halfway, or a flick (`predicted` where it was heading), it turns over; otherwise it settles back.
    func endDrag(_ translation: CGFloat, predicted: CGFloat, width: CGFloat, cornerOnRight: Bool, reduceMotion: Bool) {
        let rest = dragRest ?? flip.rest
        dragRest = nil
        let angle = MemoryCardFlip.angle(from: rest, translation: translation, width: width, cornerOnRight: cornerOnRight)
        let heading = MemoryCardFlip.angle(from: rest, translation: predicted, width: width, cornerOnRight: cornerOnRight)
        settle(at: MemoryCardFlip.settle(from: rest, angle: angle, predicted: heading), reduceMotion: reduceMotion)
    }

    /// Reduce Motion: a 0.25 s cross-fade instead of the turn.
    private func settle(at target: Double, reduceMotion: Bool) {
        withAnimation(reduceMotion ? .easeInOut(duration: 0.25) : .spring(duration: 0.45)) {
            flip.angle = target
        } completion: { [self] in
            flip.angle = MemoryCardFlip.normalized(flip.angle)
        }
        preferences?.value.side = MemoryCardFlip(angle: target).showsBack ? .mosaic : .today
    }

    /// S08 Delete all data: back to Today, as on first launch (the setting itself is reset with the others).
    func reset() {
        flip = MemoryCardFlip()
        dragRest = nil
    }

    /// U11: once, after the 10th moment.
    func showsFlipHint(moments: Int) -> Bool {
        moments >= 10 && preferences?.value.showedFlipHint == false && target == .today
    }

    func flipHintShown() {
        preferences?.value.showedFlipHint = true
    }
}

/// The screen turned edge-on: it turns to 90°, then the other side comes on from -90° the right way round, with a
/// shade on the half turning away. Animatable, so it follows a turn's spring.
struct PageTurn: ViewModifier, Animatable {
    var angle: Double

    nonisolated var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    func body(content: Content) -> some View {
        let half = angle.truncatingRemainder(dividingBy: 180)
        let shown = half < 90 ? half : half - 180
        content
            .overlay {
                LinearGradient(
                    colors: [.clear, Color.black.opacity(0.3 * abs(sin(angle * .pi / 180)))],
                    startPoint: .leading, endPoint: .trailing
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }
            .rotation3DEffect(.degrees(shown), axis: (x: 0, y: 1, z: 0), perspective: 0.45)
    }
}

/// One home side, showing while it faces the person; Reduce Motion cross-fades the sides over the same animation.
struct HomeFace: ViewModifier, Animatable {
    var angle: Double
    let side: HomeSide
    let reduceMotion: Bool

    nonisolated var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    func body(content: Content) -> some View {
        content.opacity(opacity)
    }

    private var opacity: Double {
        let turned = MemoryCardFlip.normalized(angle.truncatingRemainder(dividingBy: 360))
        let mosaic: Double
        if reduceMotion {
            // 0 at 0°, 1 at 180°, 0 again at 360°.
            mosaic = turned <= 180 ? turned / 180 : (360 - turned) / 180
        } else {
            mosaic = MemoryCardFlip(angle: turned).showsBack ? 1 : 0
        }
        return side == .mosaic ? mosaic : 1 - mosaic
    }
}
