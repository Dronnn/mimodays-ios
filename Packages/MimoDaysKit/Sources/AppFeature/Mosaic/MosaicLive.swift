@preconcurrency import AVFoundation
import DesignSystem
import Observation
import SwiftUI

/// U16: the videos on screen in the order they came on; the first four loop, the others show their poster.
@MainActor
@Observable
final class MosaicLoops {
    static let limit = 4
    private var onScreen: [UUID] = []

    func plays(_ id: UUID) -> Bool {
        onScreen.prefix(Self.limit).contains(id)
    }

    func setOnScreen(_ id: UUID, _ isOnScreen: Bool) {
        if isOnScreen {
            if !onScreen.contains(id) { onScreen.append(id) }
        } else {
            onScreen.removeAll { $0 == id }
        }
    }
}

/// U16: a video piece going round without sound: the main stream filling the piece and the selfie stream live in
/// its window, both where the poster under them has them. Until the streams are ready the poster shows.
struct MosaicLoop: View {
    let video: ViewerMoment.VideoSource
    let items: () async -> (main: AVPlayerItem, selfie: AVPlayerItem?)?
    @State private var player: ViewerVideoPlayer?

    var body: some View {
        GeometryReader { proxy in
            if let player, player.isReady {
                // The poster is the main stream's frame with the window composed on it, filling the piece.
                let canvas = MomentComposition.fitted(aspect: video.aspectRatio, in: CGRect(origin: .zero, size: proxy.size), fit: .fill)
                ZStack {
                    PlayerLayerView(player: player.main)
                        .frame(width: canvas.width, height: canvas.height)
                        .position(x: canvas.midX, y: canvas.midY)
                    if player.hasSelfie, let window = video.timing.window {
                        let rect = PhotoComposer.placement(of: window, in: canvas.size).rect.offsetBy(dx: canvas.minX, dy: canvas.minY)
                        LoopWindow(player: player.selfie, size: rect.size)
                            .position(x: rect.midX, y: rect.midY)
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task {
            guard let loaded = await items(), !Task.isCancelled else { return }
            let player = ViewerVideoPlayer(duration: video.timing.duration, silent: true)
            await player.load(main: loaded.main, selfie: loaded.selfie)
            guard !Task.isCancelled else { return player.stop() }
            self.player = player
            player.play()
        }
        .onDisappear {
            player?.stop()
            player = nil
        }
    }
}

/// The selfie window as `SelfieWindowArt` draws it on the poster: a cream frame with a soft shadow, tilted.
private struct LoopWindow: View {
    let player: AVPlayer
    let size: CGSize

    var body: some View {
        let style = SelfieWindowStyle.self
        let k = min(size.width, size.height) / style.size.width
        RoundedRectangle(cornerRadius: style.cornerRadius * k, style: .continuous)
            .fill(style.frameColor)
            .shadow(color: .black.opacity(style.shadowOpacity), radius: style.shadowBlur / 2 * k, y: style.shadowY * k)
            .overlay {
                PlayerLayerView(player: player)
                    .clipShape(RoundedRectangle(cornerRadius: style.innerCornerRadius * k, style: .continuous))
                    .padding(style.border * k)
            }
            .frame(width: size.width, height: size.height)
            .rotationEffect(style.tilt)
    }
}

/// U16's light parallax: the picture drifts against the scroll, a few percent of its height.
struct MosaicParallax: ViewModifier {
    let isOn: Bool

    func body(content: Content) -> some View {
        content.visualEffect { content, proxy in
            let viewport = proxy.bounds(of: .scrollView(axis: .vertical)) ?? .zero
            // -1 a screen above the middle, 1 a screen below it.
            let progress = viewport.height > 0 ? (proxy.size.height / 2 - viewport.midY) / viewport.height : 0
            return content.offset(y: isOn ? -min(max(progress, -1), 1) * proxy.size.height * 0.05 : 0)
        }
    }
}
