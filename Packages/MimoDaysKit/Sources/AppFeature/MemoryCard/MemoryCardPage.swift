import Core
import DesignSystem
import Persistence
import SwiftUI

/// One moment in the pager (U20-U35): the two-sided card in the moment's shape, Swap cameras and Flip under it,
/// then the voice note. The card, its buttons and the voice note's place are centred together, so every shape sits
/// in the same area. A video plays while its page is the one on screen, round and round through flips, and stops
/// when swiped away; on the back it plays on silently.
struct MemoryCardPage: View {
    let model: MomentViewerModel
    let moment: ViewerMoment
    let isCurrent: Bool
    /// The screen's width and top inset: the camera's window layout counts from them.
    let screenWidth: CGFloat
    let screenTop: CGFloat
    /// Opens Edit moment (the back's "+" links).
    let edit: () -> Void
    /// Moves to the next (+1) or previous (-1) moment (VoiceOver).
    let step: (Int) -> Void
    @State private var playback: ViewerVideoPlayer?
    /// Viewing only (Andrew, 2026-11-15): every card opens as recorded.
    @State private var swapped = false
    @State private var controlsShown = true
    @State private var flip: MemoryCardFlip
    /// The side a corner drag started from, while it lasts.
    @State private var dragRest: Double?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var direction

    /// `angle` starts it turned: snapshots of the back and of a flip half done.
    init(
        model: MomentViewerModel, moment: ViewerMoment, isCurrent: Bool, screenWidth: CGFloat, screenTop: CGFloat,
        angle: Double = 0, edit: @escaping () -> Void, step: @escaping (Int) -> Void
    ) {
        self.model = model
        self.moment = moment
        self.isCurrent = isCurrent
        self.screenWidth = screenWidth
        self.screenTop = screenTop
        self.edit = edit
        self.step = step
        _flip = State(initialValue: MemoryCardFlip(angle: angle))
    }

    private var savedLayout: PiPLayout? { moment.video?.layout ?? moment.photo?.layout }

    private var hasWindow: Bool { moment.selfiePath != nil && savedLayout != nil }

    /// The saved window, at the corner and size of the camera's layout nearest it; a move is saved on the moment.
    private var window: MemoryCardFront.Window? {
        guard hasWindow, screenWidth > 0, let saved = savedLayout else { return nil }
        let layout = MemoryCardGeometry.windowLayout(format: moment.format, screenWidth: screenWidth, topInset: screenTop)
        return MemoryCardFront.Window(
            layout: layout, placement: layout.placement(nearest: saved), rotation: saved.rotation, id: "viewer.selfieWindow"
        ) { [model, id = moment.id] placement in
            model.setWindow(PiPLayout(layout.windowFrame(placement), source: saved.source), for: id)
        }
    }

    /// The folded corner is bottom trailing.
    private var cornerOnRight: Bool { direction == .leftToRight }

    var body: some View {
        GeometryReader { proxy in
            let slot = MemoryCardGeometry.slot(page: proxy.size)
            let card = MemoryCardGeometry.card(aspectRatio: moment.format.aspectRatio, in: slot)
            let side = (slot.width - card.width) / 2
            VStack(alignment: .leading, spacing: 0) {
                twoSided(card)
                    .padding(.horizontal, side)
                buttons
                    .padding(.leading, side)
                    .padding(.top, MemoryCardGeometry.buttonsGap)
                if let voice = moment.voice, !flip.showsBack {
                    // A little wider than the card: 370 pt under a 359 pt one (U20).
                    VoicePill(model: model, id: moment.id, voice: voice, onPhoto: false)
                        .padding(.horizontal, -5.5)
                        .padding(.top, MemoryCardGeometry.pillGap)
                }
            }
            .padding(.top, MemoryCardGeometry.topGap + max(0, (slot.height - card.height) / 2))
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
        .sensoryFeedback(.impact(weight: .light), trigger: flip.showsBack)
        .onChange(of: flip.showsBack) { _, back in playback?.isOnBack = back }
        .onChange(of: model.playingVoice == moment.id) { _, playing in playback?.isDucked = playing }
        .task(id: isCurrent) {
            guard isCurrent else {
                playback?.stop()
                playback = nil
                return
            }
            guard moment.mediaType == .video, playback == nil, let items = await model.playerItems(moment.id) else { return }
            let player = ViewerVideoPlayer(duration: moment.video?.timing.duration ?? 0)
            player.isOnBack = flip.showsBack
            playback = player
            await player.load(main: items.main, selfie: items.selfie)
            player.play()
        }
        .onDisappear {
            playback?.stop()
            playback = nil
        }
    }

    // MARK: The card

    /// Front and back on one card that turns about its vertical axis, with a shade on the half turning away.
    /// Reduce Motion: the sides cross-fade.
    private func twoSided(_ card: CGSize) -> some View {
        let showsBack = flip.showsBack
        return ZStack {
            MemoryCardFront(
                pictures: MemoryCardFront.Pictures(
                    main: model.image(moment.mainPath), selfie: model.image(moment.selfiePath),
                    isVideo: moment.mediaType == .video, duration: moment.video?.timing.duration ?? 0
                ),
                playback: playback, size: card, window: window,
                swapped: swapped, cornerOnRight: cornerOnRight, controlsShown: $controlsShown,
                actions: cardActions
            )
            .modifier(CardFace(angle: reduceMotion ? (showsBack ? 180 : 0) : flip.angle, isBack: false))
            .allowsHitTesting(!showsBack)
            .accessibilityHidden(showsBack)
            MemoryCardBack(model: model, moment: moment, playback: playback, size: card, cornerOnRight: cornerOnRight, edit: edit, actions: cardActions)
                .modifier(CardFace(angle: reduceMotion ? (showsBack ? 180 : 0) : flip.angle, isBack: true))
                .allowsHitTesting(showsBack)
                .accessibilityHidden(!showsBack)
                // Drawn turned half round, so the turned card shows it the right way.
                .rotation3DEffect(reduceMotion ? .zero : .degrees(180), axis: (x: 0, y: 1, z: 0))
        }
        .background {
            MemoryCardOutline()
                .fill(ColorToken.mediaFrame.color)
                .shadow(color: ColorToken.textPrimary.color.opacity(0.16), radius: 9, y: 6)
        }
        .modifier(CardTurn(angle: reduceMotion ? 0 : flip.angle, shadeFromLeading: cornerOnRight))
        .overlay(alignment: .bottomTrailing) {
            // The fold's place, which stays put while the card turns under the finger.
            Color.clear
                .frame(width: Size.minimumTapTarget + 6, height: Size.minimumTapTarget + 6)
                .contentShape(Rectangle())
                .highPriorityGesture(flipDrag(width: card.width))
                .onTapGesture { flipOver() }
                // A hidden tap area still reaches the accessibility tree as an empty node: it says what it does.
                .accessibilityElement()
                .accessibilityLabel(Text("Flip card", bundle: .module))
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { flipOver() }
        }
    }

    private var cardActions: MemoryCardActions {
        MemoryCardActions(
            flip: { flipOver() },
            swap: hasWindow && !flip.showsBack ? { swap() } : nil,
            step: step
        )
    }

    // MARK: Flip

    private func flipDrag(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                let rest = dragRest ?? flip.rest
                dragRest = rest
                if reduceMotion { return }
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    flip.angle = MemoryCardFlip.angle(from: rest, translation: value.translation.width, width: width, cornerOnRight: cornerOnRight)
                }
            }
            .onEnded { value in
                let rest = dragRest ?? flip.rest
                dragRest = nil
                let current = MemoryCardFlip.angle(from: rest, translation: value.translation.width, width: width, cornerOnRight: cornerOnRight)
                let predicted = MemoryCardFlip.angle(from: rest, translation: value.predictedEndTranslation.width, width: width, cornerOnRight: cornerOnRight)
                settle(at: MemoryCardFlip.settle(from: rest, angle: current, predicted: predicted))
            }
    }

    private func flipOver() {
        settle(at: flip.rest + 180)
    }

    private func settle(at target: Double) {
        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.45)) {
            flip.angle = target
        } completion: {
            flip.angle = MemoryCardFlip.normalized(flip.angle)
        }
    }

    private func swap() {
        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.5)) { swapped.toggle() }
    }

    // MARK: Under the card

    private var buttons: some View {
        HStack(spacing: 12) {
            if hasWindow, !flip.showsBack {
                CardButton(glyph: .swapCameras, title: Text("Swap cameras", bundle: .module), id: "card.swap") { swap() }
                    .accessibilityAddTraits(swapped ? .isSelected : [])
            }
            CardButton(glyph: .flip, title: Text("Flip", bundle: .module), id: "card.flip") { flipOver() }
                .accessibilityLabel(Text("Flip card", bundle: .module))
        }
        .frame(minHeight: MemoryCardGeometry.buttonsHeight)
    }
}

/// The card turned about its vertical axis with perspective and a shade on the half turning away. Animatable, so the
/// shade follows the angle through a flip.
private struct CardTurn: ViewModifier, Animatable {
    var angle: Double
    let shadeFromLeading: Bool

    nonisolated var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    func body(content: Content) -> some View {
        content
            .overlay {
                LinearGradient(
                    colors: [.clear, Color.black.opacity(0.3 * abs(sin(angle * .pi / 180)))],
                    startPoint: shadeFromLeading ? .leading : .trailing, endPoint: shadeFromLeading ? .trailing : .leading
                )
                .clipShape(MemoryCardOutline())
                .allowsHitTesting(false)
            }
            .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.45)
    }
}

/// One side of the card, shown while it faces the person: the sides change over at 90° of the turn as it is drawn,
/// not when the flip is asked for.
private struct CardFace: ViewModifier, Animatable {
    var angle: Double
    let isBack: Bool

    nonisolated var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    func body(content: Content) -> some View {
        content.opacity(MemoryCardFlip(angle: angle).showsBack == isBack ? 1 : 0)
    }
}

/// What VoiceOver can do on a card (U25): flip it, swap its cameras, go to the next or previous moment.
struct MemoryCardActions {
    let flip: () -> Void
    let swap: (() -> Void)?
    let step: (Int) -> Void
}

extension View {
    /// The card's VoiceOver actions on this element.
    func memoryCardActions(_ actions: MemoryCardActions) -> some View {
        accessibilityAction(named: Text("Flip card", bundle: .module), actions.flip)
            .accessibilityAction(named: Text("Swap cameras", bundle: .module)) { actions.swap?() }
            .accessibilityAction(named: Text("Next moment", bundle: .module)) { actions.step(1) }
            .accessibilityAction(named: Text("Previous moment", bundle: .module)) { actions.step(-1) }
    }
}

/// `Card / Button`: a peach capsule with a glyph and a short label (U20).
struct CardButton: View {
    let glyph: MemoryCardGlyph.Kind
    let title: Text
    let id: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                MemoryCardGlyph(glyph)
                title
                    .textStyle(.cardButton)
                    .foregroundStyle(ColorToken.textPrimary.color)
            }
            .padding(.leading, 14)
            .padding(.trailing, 16)
            .frame(minHeight: MemoryCardGeometry.buttonsHeight)
            .background(Capsule().fill(ColorToken.accentPeach.color))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }
}
