@preconcurrency import AVFoundation
import Core
import DesignSystem
import Observation
import SwiftUI

/// Plays a composed video for the viewer: play and pause, the sound, where it is and seeking (M06).
@MainActor
@Observable
final class ViewerVideoPlayer {
    let player = AVPlayer()
    private(set) var time: Double = 0
    private(set) var duration: Double
    private(set) var isPlaying = false
    var isMuted = false {
        didSet { player.isMuted = isMuted }
    }

    private var timeObserver: Any?
    private var endObserver: (any NSObjectProtocol)?

    init(duration: Double) {
        self.duration = duration
    }

    func load(_ video: VideoComposer.Composed) {
        let item = video.playerItem()
        player.replaceCurrentItem(with: item)
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 20), queue: .main) { [weak self] time in
            MainActor.assumeIsolated { self?.time = time.seconds }
        }
        endObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.isPlaying = false
                self?.seek(to: 0)
            }
        }
    }

    func toggle() {
        isPlaying ? pause() : play()
    }

    func play() {
        player.play()
        isPlaying = true
    }

    func pause() {
        player.pause()
        isPlaying = false
    }

    func seek(to seconds: Double) {
        time = seconds
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func stop() {
        pause()
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        timeObserver = nil
        endObserver = nil
        player.replaceCurrentItem(with: nil)
    }
}

/// M06: the video fills the screen; its words, voice note, scrubber, pause and sound sit at the bottom in cream.
/// It plays when its page is the one on screen and stops when swiped away.
struct VideoPage: View {
    let model: MomentViewerModel
    let moment: ViewerMoment
    let isCurrent: Bool
    @State private var playback: ViewerVideoPlayer?
    @State private var poster: UIImage?

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black
                .overlay {
                    if let playback {
                        PlayerLayerView(player: playback.player)
                    } else if let image = model.image(moment.mainPath) {
                        Image(uiImage: image).resizable().scaledToFill()
                    }
                }
                .clipped()
                .ignoresSafeArea()
                .accessibilityElement()
                .accessibilityLabel(Text("Video", bundle: .module))
                .accessibilityAddTraits(.isImage)
            LinearGradient(colors: [.clear, ColorToken.mediaScrim.color], startPoint: .top, endPoint: .bottom)
                .frame(height: 360)
                .ignoresSafeArea()
                .allowsHitTesting(false)
            controls
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
        }
        .task(id: isCurrent) {
            guard isCurrent else {
                playback?.stop()
                playback = nil
                return
            }
            guard playback == nil, let composed = await model.composedVideo(moment.id) else { return }
            let player = ViewerVideoPlayer(duration: moment.video?.timing.duration ?? 0)
            player.load(composed)
            playback = player
            player.play()
        }
        .onDisappear {
            playback?.stop()
            playback = nil
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 0) {
            MomentWords(moment: moment, onPhoto: true)
            if let voice = moment.voice {
                VoicePill(model: model, id: moment.id, voice: voice, onPhoto: true)
                    .padding(.top, 14)
            }
            scrubber
                .padding(.top, 24)
            ZStack {
                Button { playback?.toggle() } label: {
                    (playback?.isPlaying == true ? Icon.glyphPause : .glyphPlay).image
                        .resizable()
                        .scaledToFit()
                        .frame(width: 32, height: 32)
                        .frame(width: Size.minimumTapTarget, height: Size.minimumTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(playback?.isPlaying == true ? "Pause" : "Play", bundle: .module))
                .accessibilityIdentifier("viewer.play")
                HStack {
                    Spacer()
                    Button { playback?.isMuted.toggle() } label: {
                        (playback?.isMuted == true ? Icon.glyphMute : .glyphSpeaker).image
                            .resizable()
                            .frame(width: 24, height: 24)
                            .frame(width: Size.minimumTapTarget, height: Size.minimumTapTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(playback?.isMuted == true ? "Sound off" : "Sound on", bundle: .module))
                }
            }
            .padding(.top, 8)
        }
        .foregroundStyle(ColorToken.mediaFrame.color)
    }

    private var scrubber: some View {
        let duration = max(playback?.duration ?? moment.video?.timing.duration ?? 0, 0.1)
        let time = min(playback?.time ?? 0, duration)
        return VStack(spacing: 6) {
            Slider(value: Binding(get: { time }, set: { playback?.seek(to: $0) }), in: 0...duration)
                .tint(ColorToken.actionCoral.color)
                .accessibilityLabel(Text("Playback position", bundle: .module))
                .accessibilityValue(Text(Duration.seconds(time.rounded()), format: .time(pattern: .minuteSecond)))
            HStack {
                Text(Duration.seconds(time.rounded()), format: .time(pattern: .minuteSecond))
                Spacer()
                Text(Duration.seconds(duration.rounded()), format: .time(pattern: .minuteSecond))
            }
            .textStyle(.tileBadge)
            .accessibilityHidden(true)
        }
        .environment(\.layoutDirection, .leftToRight)
    }
}

/// An `AVPlayerLayer` filling its view.
struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context _: Context) -> LayerView {
        let view = LayerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ view: LayerView, context _: Context) {
        view.playerLayer.player = player
    }

    final class LayerView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}
