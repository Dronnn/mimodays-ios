@preconcurrency import AVFoundation
import Core
import DesignSystem
import Observation
import Persistence
import SwiftUI

/// Plays a saved video on the Memory Card: the main stream with its sound, and the selfie stream (when there is
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
    /// The sound button.
    var isMuted = false {
        didSet { applySound() }
    }

    /// The card's back is showing: it plays on, silent (U35).
    var isOnBack = false {
        didSet { applySound() }
    }

    /// The voice note is playing over it.
    var isDucked = false {
        didSet { applySound() }
    }

    private var timeObserver: Any?
    private var endObserver: (any NSObjectProtocol)?
    /// A Mosaic piece's loop (U16): no sound, and other apps' sound left alone.
    private let isSilent: Bool

    init(duration: Double, silent: Bool = false) {
        self.duration = duration
        isSilent = silent
        main.isMuted = silent
        selfie.isMuted = true
        // Started together at one host time, which needs players that don't wait on their own.
        main.automaticallyWaitsToMinimizeStalling = false
        selfie.automaticallyWaitsToMinimizeStalling = false
    }

    private func applySound() {
        main.isMuted = isSilent || isMuted || isOnBack
        main.volume = isDucked ? 0.2 : 1
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
            // Round and round for as long as the card is on screen (U35).
            MainActor.assumeIsolated { self?.loop() }
        }
        isReady = item.status == .readyToPlay
    }

    /// Back to the start without a stop: both streams from zero at one host time.
    private func loop() {
        guard isPlaying else { return seek(to: 0) }
        time = 0
        start(at: .zero)
    }

    func toggle() {
        isPlaying ? pause() : play()
    }

    /// Both streams start at the same host time from the main one's position.
    func play() {
        guard isReady else { return }
        if !isSilent { try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback) }
        start(at: main.currentTime())
        isPlaying = true
    }

    private func start(at time: CMTime) {
        let hostTime = CMTimeAdd(CMClockGetTime(CMClockGetHostTimeClock()), CMTime(value: 1, timescale: 20))
        main.setRate(1, time: time, atHostTime: hostTime)
        if hasSelfie { selfie.setRate(1, time: time, atHostTime: hostTime) }
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
