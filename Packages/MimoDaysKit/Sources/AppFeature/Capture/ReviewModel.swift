@preconcurrency import AVFoundation
import Core
import Foundation
import ImageIO
import Observation
import UIKit

/// Review (C07), or C13d after a recording that stopped early: the capture before it is kept.
@MainActor
@Observable
final class ReviewModel {
    enum Playback: Equatable {
        /// The first frame, with the adjustable selfie window over it.
        case stopped
        case playing
        case paused
    }

    /// One line (Andrew, 2026-11-13: a short caption; the longer note is C08).
    static let captionLimit = 80

    let capture: CaptureResult
    /// The review's own placement: moving the window here doesn't change the camera's default.
    var window: CameraSettings.SelfieWindow
    var caption = "" {
        didSet { if caption.count > Self.captionLimit { caption = String(caption.prefix(Self.captionLimit)) } }
    }

    /// Where the window's frame sits in the shown media, reported by the view; the moment is composed with it.
    var windowFrame: SelfieWindowFrame?
    private(set) var main: UIImage?
    private(set) var selfie: UIImage?
    private(set) var playback = Playback.stopped
    let player = AVPlayer()
    private var endObserver: (any NSObjectProtocol)?

    init(capture: CaptureResult) {
        self.capture = capture
        window = capture.window ?? CameraSettings.SelfieWindow()
    }

    var hasSelfie: Bool { capture.selfieURL != nil }

    var video: CapturedVideo? {
        if case let .video(video) = capture.media { video } else { nil }
    }

    /// C13d: why the recording stopped early.
    var interruption: CaptureInterruption? { video?.interruption }

    /// Whole seconds an interrupted recording kept ("Save 6 seconds", "at 0:06").
    var keptSeconds: Int { max(1, Int((video?.duration ?? 0).rounded())) }

    /// Width / height of the main frame, upright; 3:4 until it has loaded.
    var aspectRatio: CGFloat {
        guard let main, main.size.height > 0 else { return 3.0 / 4.0 }
        return main.size.width / main.size.height
    }

    /// First frames for the still view. The selfie is taken where it lines up with the main frame's start.
    func load() async {
        main = await Self.still(capture.mainURL, maxPixelSize: 2048, at: 0)
        if let selfieURL = capture.selfieURL {
            selfie = await Self.still(selfieURL, maxPixelSize: 600, at: max(0, -(video?.selfieOffset ?? 0)))
        }
    }

    /// Play from the start with sound, pause, or carry on.
    func togglePlayback() async {
        switch playback {
        case .playing:
            player.pause()
            playback = .paused
        case .paused:
            player.play()
            playback = .playing
        case .stopped:
            guard let video, let composed = try? await VideoComposer.compose(
                mainURL: video.mainURL, selfieURL: video.selfieURL, timing: timing(video)
            ) else { return }
            let item = composed.playerItem()
            observeEnd(of: item)
            player.replaceCurrentItem(with: item)
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            player.play()
            playback = .playing
        }
    }

    func stopPlayback() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        playback = .stopped
    }

    /// What Save keeps.
    func draft(promptID: UUID?) -> MomentDraft {
        MomentDraft(capture: capture, caption: caption, window: hasSelfie ? windowFrame : nil, promptID: promptID)
    }

    /// Retake / Record again: nothing is kept.
    func discard() {
        stopPlayback()
        capture.discardFiles()
    }

    /// What a saved video needs to play composed again.
    func timing(_ video: CapturedVideo) -> VideoTiming {
        VideoTiming(
            duration: video.duration, selfieOffset: video.selfieOffset, hasAudio: video.hasAudio,
            mainPosition: video.mainPosition, window: video.selfieURL == nil ? nil : windowFrame
        )
    }

    private func observeEnd(of item: AVPlayerItem) {
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.stopPlayback() }
        }
    }

    /// An upright still of a photo, or of a video at `seconds`.
    nonisolated static func still(_ url: URL, maxPixelSize: Int, at seconds: TimeInterval) async -> UIImage? {
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(source) > 0,
           let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
               kCGImageSourceCreateThumbnailFromImageAlways: true,
               kCGImageSourceCreateThumbnailWithTransform: true,
               kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
           ] as CFDictionary) {
            return UIImage(cgImage: image)
        }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxPixelSize, height: maxPixelSize)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 30)
        guard let (image, _) = try? await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)) else { return nil }
        return UIImage(cgImage: image)
    }
}
