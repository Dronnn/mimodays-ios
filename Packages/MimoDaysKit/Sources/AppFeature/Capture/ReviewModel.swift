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
    /// C08 counter: "86 / 500".
    static let noteLimit = 500
    /// C09: "0:12 / 1:00".
    static let voiceLimit: TimeInterval = 60
    /// C10 waveform bars.
    static let voiceBars = 38

    let capture: CaptureResult
    /// The surprise this capture answers, if it was opened in time.
    let promptID: UUID?
    /// The review's own placement: moving the window here doesn't change the camera's default.
    var window: CameraSettings.SelfieWindow {
        didSet { keepDraft() }
    }

    var caption = "" {
        didSet {
            if caption.count > Self.captionLimit { caption = String(caption.prefix(Self.captionLimit)) }
            keepDraft()
        }
    }

    /// C08's text; empty means no note.
    var note = "" {
        didSet {
            if note.count > Self.noteLimit { note = String(note.prefix(Self.noteLimit)) }
            keepDraft()
        }
    }

    /// C09/C10; nil means no voice note.
    var voice: ReviewVoiceNote? {
        didSet { keepDraft() }
    }

    private let drafts: ReviewDraftStore?
    private let services: VoiceServices

    /// Where the window's frame sits in the shown media, reported by the view; the moment is composed with it.
    var windowFrame: SelfieWindowFrame?
    private(set) var main: UIImage?
    private(set) var selfie: UIImage?
    private(set) var playback = Playback.stopped
    let player = AVPlayer()
    private var endObserver: (any NSObjectProtocol)?
    /// C10 waveform, one level (0...1) per bar.
    private(set) var voiceLevels: [Float] = []
    private(set) var playsVoice = false
    let voicePlayer = AVPlayer()
    private var voiceEndObserver: (any NSObjectProtocol)?
    private var transcription: Task<Void, Never>?

    /// A new capture; with `drafts` it is kept on disk until saved or retaken.
    init(capture: CaptureResult, promptID: UUID? = nil, drafts: ReviewDraftStore? = nil, voice services: VoiceServices = .simulated) {
        self.capture = capture
        self.promptID = promptID
        self.drafts = drafts
        self.services = services
        window = capture.window ?? CameraSettings.SelfieWindow()
        keepDraft()
    }

    /// The review iOS closed mid-way, as it was.
    init(draft: ReviewDraft, drafts: ReviewDraftStore?, voice services: VoiceServices = .simulated) {
        capture = draft.capture
        promptID = draft.promptID
        self.drafts = drafts
        self.services = services
        window = draft.window
        caption = draft.caption
        note = draft.note
        voice = draft.voice
        if let voice = draft.voice {
            voiceLevels = VoiceWaveform.read(voice.url, bars: Self.voiceBars)?.levels ?? []
            transcribe()
        }
    }

    /// Something Retake would throw away besides the capture.
    var hasAnnotations: Bool { !note.isEmpty || voice != nil }

    private func keepDraft() {
        drafts?.save(ReviewDraft(capture: capture, caption: caption, note: note, window: window, promptID: promptID, voice: voice))
    }

    /// The pending draft is done with: the moment was saved.
    func clearDraft() {
        stopVoice()
        if drafts == nil, let voice { try? FileManager.default.removeItem(at: voice.url) }
        drafts?.clear()
    }

    // MARK: Voice note

    /// A recorder for C09, writing next to the capture.
    func makeVoiceRecording() throws -> VoiceRecording {
        let url = try drafts?.newVoiceURL() ?? CaptureFiles.temporaryURL("m4a")
        Task { [transcriber = services.transcriber] in await transcriber.prepare() }
        return VoiceRecording(recorder: services.makeRecorder(), url: url, limit: Self.voiceLimit)
    }

    /// A finished C09 recording becomes the voice note, in place of any earlier one. Under half a second is dropped.
    func addVoice(at url: URL, recordedAt: Date) {
        guard let read = VoiceWaveform.read(url, bars: Self.voiceBars), read.duration >= 0.5 else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        removeVoice()
        voiceLevels = read.levels
        voice = ReviewVoiceNote(url: url, duration: read.duration, recordedAt: recordedAt)
        transcribe()
    }

    func removeVoice() {
        stopVoice()
        transcription?.cancel()
        transcription = nil
        if let voice { try? FileManager.default.removeItem(at: voice.url) }
        voice = nil
        voiceLevels = []
    }

    /// Save waits for this: seconds on device, since the model is never downloaded here.
    func finishTranscription() async {
        await transcription?.value
    }

    private func transcribe() {
        guard let voice, voice.transcript == nil else { return }
        let url = voice.url
        let transcriber = services.transcriber
        transcription = Task { [weak self] in
            let text = await transcriber.transcribe(url)
            guard let self, !Task.isCancelled, self.voice?.url == url, let text else { return }
            self.voice?.transcript = text
        }
    }

    /// Play from the start, pause, or carry on. The video stops while the voice note plays.
    func toggleVoice() {
        guard let voice else { return }
        if playsVoice {
            voicePlayer.pause()
            playsVoice = false
            return
        }
        stopPlayback()
        if voicePlayer.currentItem == nil {
            let item = AVPlayerItem(url: voice.url)
            if let voiceEndObserver { NotificationCenter.default.removeObserver(voiceEndObserver) }
            voiceEndObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.stopVoice() }
            }
            voicePlayer.replaceCurrentItem(with: item)
        }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        voicePlayer.play()
        playsVoice = true
    }

    func stopVoice() {
        voicePlayer.pause()
        voicePlayer.replaceCurrentItem(with: nil)
        playsVoice = false
    }

    /// How much of the voice note has played, 0...1.
    var voiceProgress: Double {
        guard let voice, voice.duration > 0, voicePlayer.currentItem != nil else { return 0 }
        return min(1, max(0, voicePlayer.currentTime().seconds / voice.duration))
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
            stopVoice()
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
    var momentDraft: MomentDraft {
        MomentDraft(capture: capture, caption: caption, note: note, window: hasSelfie ? windowFrame : nil, promptID: promptID, voice: voice)
    }

    /// Retake / Record again: nothing is kept.
    func discard() {
        stopPlayback()
        removeVoice()
        capture.discardFiles()
        drafts?.clear()
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
