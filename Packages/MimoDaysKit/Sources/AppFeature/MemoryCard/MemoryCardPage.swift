import Core
import DesignSystem
import Persistence
import SwiftUI

/// One moment in the pager (U20-U24): the card in the moment's shape, Swap cameras under it, then the voice note.
/// The card, its buttons and the voice note's place are centred together, so every shape sits in the same area.
/// A video plays while its page is the one on screen, round and round, and stops when swiped away.
struct MemoryCardPage: View {
    let model: MomentViewerModel
    let moment: ViewerMoment
    let isCurrent: Bool
    /// The screen's width and top inset: the camera's window layout counts from them.
    let screenWidth: CGFloat
    let screenTop: CGFloat
    @State private var playback: ViewerVideoPlayer?
    /// Viewing only (Andrew, 2026-11-15): every card opens as recorded.
    @State private var swapped = false
    @State private var controlsShown = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var hasWindow: Bool {
        moment.selfiePath != nil && (moment.video?.layout ?? moment.photo?.layout) != nil
    }

    var body: some View {
        GeometryReader { proxy in
            let slot = MemoryCardGeometry.slot(page: proxy.size)
            let card = MemoryCardGeometry.card(aspectRatio: moment.format.aspectRatio, in: slot)
            let side = (slot.width - card.width) / 2
            VStack(alignment: .leading, spacing: 0) {
                MemoryCardFront(
                    model: model, moment: moment, playback: playback, size: card,
                    windowLayout: hasWindow && screenWidth > 0
                        ? MemoryCardGeometry.windowLayout(format: moment.format, screenWidth: screenWidth, topInset: screenTop)
                        : nil,
                    swapped: swapped, controlsShown: $controlsShown
                )
                .background {
                    MemoryCardOutline()
                        .fill(ColorToken.mediaFrame.color)
                        .shadow(color: ColorToken.textPrimary.color.opacity(0.16), radius: 9, y: 6)
                }
                .padding(.horizontal, side)
                buttons
                    .padding(.leading, side)
                    .padding(.top, MemoryCardGeometry.buttonsGap)
                if let voice = moment.voice {
                    // A little wider than the card: 370 pt under a 359 pt one (U20).
                    VoicePill(model: model, id: moment.id, voice: voice, onPhoto: false)
                        .padding(.horizontal, -5.5)
                        .padding(.top, MemoryCardGeometry.pillGap)
                }
            }
            .padding(.top, MemoryCardGeometry.topGap + max(0, (slot.height - card.height) / 2))
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
        .task(id: isCurrent) {
            guard isCurrent else {
                playback?.stop()
                playback = nil
                return
            }
            guard moment.mediaType == .video, playback == nil, let items = await model.playerItems(moment.id) else { return }
            let player = ViewerVideoPlayer(duration: moment.video?.timing.duration ?? 0)
            playback = player
            await player.load(main: items.main, selfie: items.selfie)
            player.play()
        }
        .onDisappear {
            playback?.stop()
            playback = nil
        }
    }

    private var buttons: some View {
        HStack(spacing: 12) {
            if hasWindow {
                CardButton(glyph: .swapCameras, title: Text("Swap cameras", bundle: .module), id: "card.swap") {
                    withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.5)) { swapped.toggle() }
                }
                .accessibilityAddTraits(swapped ? .isSelected : [])
            }
        }
        .frame(minHeight: MemoryCardGeometry.buttonsHeight)
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
