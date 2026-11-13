import AVFoundation
import SwiftUI

/// Plays a composed video in a loop, muted unless `isMuted` is false (review C07, moment M06).
struct ComposedVideoView: UIViewRepresentable {
    let video: VideoComposer.Composed
    var isMuted = true

    func makeUIView(context _: Context) -> PlayerView {
        let view = PlayerView()
        view.play(video, isMuted: isMuted)
        return view
    }

    func updateUIView(_ view: PlayerView, context _: Context) {
        view.player.isMuted = isMuted
    }

    static func dismantleUIView(_ view: PlayerView, coordinator _: ()) {
        view.player.pause()
    }

    final class PlayerView: UIView {
        let player = AVQueuePlayer()
        private var looper: AVPlayerLooper?

        override static var layerClass: AnyClass { AVPlayerLayer.self }

        func play(_ video: VideoComposer.Composed, isMuted: Bool) {
            let layer = layer as? AVPlayerLayer
            layer?.player = player
            layer?.videoGravity = .resizeAspectFill
            player.isMuted = isMuted
            looper = AVPlayerLooper(player: player, templateItem: video.playerItem())
            player.play()
        }
    }
}
