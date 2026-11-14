@preconcurrency import AVFoundation
import Core
import DesignSystem
import Observation
import Persistence
import SwiftUI

/// Plays a saved video for the viewer: the main stream with its sound, and the selfie stream (when there is
/// one) in step with it for the live window. The two stay separate files; they become one only on export.
@MainActor
@Observable
final class ViewerVideoPlayer {
    let main = AVPlayer()
    let selfie = AVPlayer()
    private(set) var hasSelfie = false
    private(set) var isReady = false
    private(set) var time: Double = 0
    private(set) var duration: Double
    private(set) var isPlaying = false
    var isMuted = false {
        didSet { main.isMuted = isMuted }
    }

    private var timeObserver: Any?
    private var endObserver: (any NSObjectProtocol)?

    init(duration: Double) {
        self.duration = duration
        selfie.isMuted = true
        // Started together at one host time, which needs players that don't wait on their own.
        main.automaticallyWaitsToMinimizeStalling = false
        selfie.automaticallyWaitsToMinimizeStalling = false
    }

    func load(main item: AVPlayerItem, selfie selfieItem: AVPlayerItem?) async {
        main.replaceCurrentItem(with: item)
        selfie.replaceCurrentItem(with: selfieItem)
        hasSelfie = selfieItem != nil
        await Self.ready(item)
        if let selfieItem { await Self.ready(selfieItem) }
        if item.status == .readyToPlay { duration = max(duration, item.duration.seconds.isFinite ? item.duration.seconds : 0) }
        timeObserver = main.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 20), queue: .main) { [weak self] time in
            MainActor.assumeIsolated { self?.time = time.seconds }
        }
        endObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.pause()
                self?.seek(to: 0)
            }
        }
        isReady = item.status == .readyToPlay
    }

    func toggle() {
        isPlaying ? pause() : play()
    }

    /// Both streams start at the same host time from the main one's position.
    func play() {
        guard isReady else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        let time = main.currentTime()
        let start = CMTimeAdd(CMClockGetTime(CMClockGetHostTimeClock()), CMTime(value: 1, timescale: 20))
        main.setRate(1, time: time, atHostTime: start)
        if hasSelfie { selfie.setRate(1, time: time, atHostTime: start) }
        isPlaying = true
    }

    func pause() {
        main.pause()
        selfie.pause()
        isPlaying = false
        if hasSelfie { selfie.seek(to: main.currentTime(), toleranceBefore: .zero, toleranceAfter: .zero) }
    }

    func seek(to seconds: Double) {
        time = seconds
        let target = CMTime(seconds: seconds, preferredTimescale: 600)
        main.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
        if hasSelfie { selfie.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) }
    }

    func stop() {
        pause()
        if let timeObserver { main.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        timeObserver = nil
        endObserver = nil
        main.replaceCurrentItem(with: nil)
        selfie.replaceCurrentItem(with: nil)
        isReady = false
    }

    /// Until the item is ready or failed, at most a few seconds (local files are ready almost at once).
    private static func ready(_ item: AVPlayerItem) async {
        for _ in 0..<150 where item.status == .unknown {
            try? await Task.sleep(for: .milliseconds(20))
        }
    }
}

/// M06: the whole video from the top edge, as the camera showed it, with the selfie window where it was
/// recorded. The window moves and changes size as while recording; where it ends up is kept and is what
/// sharing exports. Words, voice note, scrubber, pause and sound sit at the bottom in cream.
/// It plays when its page is the one on screen and stops when swiped away.
struct VideoPage: View {
    let model: MomentViewerModel
    let moment: ViewerMoment
    let isCurrent: Bool
    /// The screen's top inset (status bar), which the camera's window layout counts from.
    let topInset: CGFloat
    @State private var playback: ViewerVideoPlayer?
    /// Playing before a scrub started.
    @State private var resumesAfterScrub: Bool?

    var body: some View {
        ZStack(alignment: .bottom) {
            GeometryReader { proxy in
                media(in: proxy.size)
            }
            .ignoresSafeArea()
            controls
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
                // The words may sit over the media's lower edge: it fades into the page's black above them.
                .background {
                    VStack(spacing: 0) {
                        LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                            .frame(height: 96)
                        Color.black
                    }
                    .padding(.top, -96)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                }
        }
        .task(id: isCurrent) {
            guard isCurrent else {
                playback?.stop()
                playback = nil
                return
            }
            guard playback == nil, let items = await model.playerItems(moment.id) else { return }
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

    // MARK: Media

    /// The main stream aspect-fit at the top, the selfie window laid out as the camera did and drawn at the
    /// size the media has here.
    @ViewBuilder
    private func media(in size: CGSize) -> some View {
        let aspectRatio = moment.video?.aspectRatio ?? 9.0 / 16.0
        let width = min(size.width, size.height * aspectRatio)
        let shown = CGSize(width: width, height: width / aspectRatio)
        ZStack(alignment: .topLeading) {
            ZStack {
                if let image = model.image(moment.mainPath) {
                    Image(uiImage: image).resizable().scaledToFill()
                }
                if let playback {
                    PlayerLayerView(player: playback.main)
                }
            }
            .frame(width: shown.width, height: shown.height)
            .clipped()
            .accessibilityElement()
            .accessibilityLabel(Text("Video", bundle: .module))
            .accessibilityAddTraits(.isImage)
            if let layout = moment.video?.layout, size.width > 0 {
                ViewerSelfieWindow(model: model, momentID: moment.id, saved: layout, screenWidth: size.width, topInset: topInset, shown: shown) {
                    ZStack {
                        if let image = model.image(moment.selfiePath) {
                            Image(uiImage: image).resizable().scaledToFill()
                        }
                        if let playback, playback.hasSelfie {
                            PlayerLayerView(player: playback.selfie)
                        }
                    }
                }
            }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .background(Color.black)
    }

    // MARK: Controls

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
                        .frame(width: 40, height: 40)
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

    /// M06 scrubber: a 4 pt track, coral up to where it is, a 16 pt cream knob; drag anywhere on it to seek.
    private var scrubber: some View {
        let duration = max(playback?.duration ?? moment.video?.timing.duration ?? 0, 0.1)
        let time = min(playback?.time ?? 0, duration)
        return VStack(spacing: 6) {
            GeometryReader { proxy in
                let progress = CGFloat(time / duration)
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(ColorToken.mediaFrame.color.opacity(0.3))
                        .frame(height: 4)
                    Capsule()
                        .fill(ColorToken.actionCoral.color)
                        .frame(width: max(4, proxy.size.width * progress), height: 4)
                    Circle()
                        .fill(ColorToken.mediaFrame.color)
                        .frame(width: 16, height: 16)
                        .offset(x: proxy.size.width * progress - 8)
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if resumesAfterScrub == nil {
                                resumesAfterScrub = playback?.isPlaying ?? false
                                playback?.pause()
                            }
                            let fraction = min(max(value.location.x / max(proxy.size.width, 1), 0), 1)
                            playback?.seek(to: duration * fraction)
                        }
                        .onEnded { _ in
                            if resumesAfterScrub == true { playback?.play() }
                            resumesAfterScrub = nil
                        }
                )
            }
            .frame(height: Size.minimumTapTarget / 2)
            .accessibilityElement()
            .accessibilityLabel(Text("Playback position", bundle: .module))
            .accessibilityValue(Text(Duration.seconds(time.rounded()), format: .time(pattern: .minuteSecond)))
            .accessibilityAdjustableAction { direction in
                let step = direction == .increment ? 5.0 : -5.0
                playback?.seek(to: min(max(time + step, 0), duration))
            }
            HStack {
                Text(Duration.seconds(time.rounded()), format: .time(pattern: .minuteSecond))
                Spacer()
                Text(Duration.seconds(duration.rounded()), format: .time(pattern: .minuteSecond))
            }
            .textStyle(.scrubTime)
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
