@preconcurrency import AVFoundation
import Core
import Foundation
import ImageIO
import Observation
import Persistence
import UIKit

/// Review (C07), or C13d after a recording that stopped early: the capture before it is kept.
@MainActor
@Observable
final class ReviewModel {
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
    /// The saved moment's id, from the start (rev-capture 19).
    let momentID: UUID
    /// P8.8: the moment this captures again.
    let repeatOf: UUID?
    /// P8.4, P8.10.
    var tags: [String] = [] {
        didSet { keepDraft() }
    }
    var mood: Mood? {
        didSet { keepDraft() }
    }
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

    /// C11; nil means no place.
    var place: ReviewPlace? {
        didSet { keepDraft() }
    }

    /// A place or "No place" was picked: a late location fix no longer fills it in.
    private(set) var placeWasChosen = false {
        didSet { keepDraft() }
    }

    /// C11's current location row: the city this iPhone is in now.
    private(set) var currentPlace: ReviewPlace?
    private(set) var isLocating = false
    /// C11's nearby rows, looked up when the sheet first shows after a fix.
    private(set) var nearby: [PlaceSuggestion] = []
    private var fix: GeoPoint?
    private var nearbyFix: GeoPoint?
    /// A new capture takes the city by itself once location is allowed; a review restored after a relaunch doesn't,
    /// since the iPhone may have moved since.
    private let fillsPlace: Bool

    private let drafts: ReviewDraftStore?
    private let services: VoiceServices
    private let places: PlaceServices

    /// Where the window's frame sits in the shown media, reported by the view; the moment is composed with it.
    var windowFrame: SelfieWindowFrame?
    private(set) var main: UIImage?
    private(set) var selfie: UIImage?
    /// Both streams in step on the card, round and round, as the viewer plays them (U42).
    private(set) var playback: ViewerVideoPlayer?
    /// C10 waveform, one level (0...1) per bar.
    private(set) var voiceLevels: [Float] = []
    private(set) var playsVoice = false
    /// The voice note being recorded, while its sheet is up.
    @ObservationIgnored private weak var voiceRecording: VoiceRecording?
    let voicePlayer = AVPlayer()
    private var voiceEndObserver: (any NSObjectProtocol)?
    private var transcription: Task<Void, Never>?

    /// A new capture; with `drafts` it is kept on disk until saved or retaken.
    init(
        capture: CaptureResult, promptID: UUID? = nil, repeatOf: UUID? = nil, drafts: ReviewDraftStore? = nil,
        voice services: VoiceServices = .simulated, places: PlaceServices = .simulated
    ) {
        self.capture = capture
        self.promptID = promptID
        self.repeatOf = repeatOf
        self.drafts = drafts
        self.services = services
        self.places = places
        fillsPlace = true
        momentID = UUID()
        window = capture.window ?? CameraSettings.SelfieWindow()
        drafts?.claim.writer = self
        keepDraft()
    }

    /// The review iOS closed mid-way, as it was.
    init(draft: ReviewDraft, drafts: ReviewDraftStore?, voice services: VoiceServices = .simulated, places: PlaceServices = .simulated) {
        capture = draft.capture
        promptID = draft.promptID
        repeatOf = draft.repeatOf
        tags = draft.tags ?? []
        mood = draft.mood
        self.drafts = drafts
        self.services = services
        self.places = places
        fillsPlace = false
        momentID = draft.momentID ?? UUID()
        place = draft.place
        placeWasChosen = draft.placeWasChosen
        window = draft.window
        caption = draft.caption
        note = draft.note
        voice = draft.voice
        drafts?.claim.writer = self
        if let voice = draft.voice {
            voiceLevels = VoiceWaveform.read(voice.url, bars: Self.voiceBars)?.levels ?? []
            transcribe()
        }
    }

    /// Something Retake would throw away besides the capture: a place counts once it was picked, not the city found
    /// by itself.
    var hasAnnotations: Bool { !note.isEmpty || voice != nil || hasCaption || hasChosenPlace }

    var hasCaption: Bool { !caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var hasChosenPlace: Bool { placeWasChosen && place != nil }

    /// Retaken or saved: the draft file belongs to the next capture now, and a lookup still finishing for this one
    /// mustn't write over it.
    private var isFinished = false

    /// Only the newest Review writes the draft: one left open behind a link, its draft reopened (or retaken and
    /// followed by the next capture) since, mustn't write over it when a late lookup lands.
    private func keepDraft() {
        guard !isFinished, let drafts, drafts.claim.writer === self else { return }
        // Nor bring back one whose files are gone.
        guard FileManager.default.fileExists(atPath: capture.mainURL.path) else { return }
        drafts.save(ReviewDraft(
            capture: capture, caption: caption, note: note, window: window, promptID: promptID, repeatOf: repeatOf,
            tags: tags.isEmpty ? nil : tags, mood: mood, voice: voice, place: place, placeWasChosen: placeWasChosen,
            momentID: momentID
        ))
    }

    /// The pending draft is done with: the moment was saved.
    func clearDraft() {
        isFinished = true
        stopVoice()
        if drafts == nil, let voice { try? FileManager.default.removeItem(at: voice.url) }
        // A save that ended after its Review was left: the draft there may be the next capture's by now.
        if let drafts, let onDisk = drafts.load(), onDisk.capture.mainURL.lastPathComponent != capture.mainURL.lastPathComponent { return }
        drafts?.clear()
    }

    // MARK: Place

    /// One fix and its city, once per review. Call only with location allowed. With S05's Save a place off,
    /// this iPhone's position isn't asked for at all; a place can still be picked by name.
    func locate() async {
        let privacy = places.privacy()
        guard privacy.savesPlace, fix == nil, !isLocating else { return }
        isLocating = true
        defer { isLocating = false }
        guard let fix = try? await places.location.currentLocation(), !isFinished else { return }
        self.fix = fix
        let city = await places.lookup.city(at: fix)
        guard !isFinished else { return }
        currentPlace = ReviewPlace.current(city: city, at: fix, precision: privacy.precision)
        if fillsPlace, !placeWasChosen, place == nil { place = currentPlace }
    }

    /// A row in C11; nil is "No place".
    func choose(_ place: ReviewPlace?) {
        self.place = place
        placeWasChosen = true
    }

    /// Up to three places around the fix, once per fix.
    func loadNearby() async {
        guard let fix, nearbyFix != fix else { return }
        nearbyFix = fix
        nearby = Array(await places.lookup.nearby(fix).prefix(3))
    }

    func searchPlaces(_ text: String) async -> [PlaceSuggestion] {
        await places.lookup.search(text, near: fix)
    }

    func recentPlaces() -> [RecentPlace] {
        places.recents()
    }

    // MARK: Voice note

    /// A recorder for C09, writing next to the capture.
    func makeVoiceRecording() throws -> VoiceRecording {
        let url = try drafts?.newVoiceURL() ?? CaptureFiles.temporaryURL("m4a")
        Task { [transcriber = services.transcriber] in await transcriber.prepare() }
        let recording = VoiceRecording(recorder: services.makeRecorder(), url: url, limit: Self.voiceLimit)
        voiceRecording = recording
        return recording
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

    /// Save doesn't wait for the words: what isn't done yet is worked out into the saved note (rev-capture 18).
    /// The words as Review shows them, once worked out.
    func finishTranscription() async {
        await transcription?.value
    }

    func cancelTranscription() {
        transcription?.cancel()
        transcription = nil
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

    /// Play from the start, pause, or carry on. The video pauses while the voice note plays.
    func toggleVoice() {
        guard let voice else { return }
        if playsVoice {
            voicePlayer.pause()
            playsVoice = false
            return
        }
        playback?.pause()
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

    private func pauseVoice() {
        guard playsVoice else { return }
        voicePlayer.pause()
        playsVoice = false
    }

    func stopVoice() {
        voicePlayer.pause()
        voicePlayer.replaceCurrentItem(with: nil)
        playsVoice = false
        // Its item is gone: the observer for its end goes too, not left behind with each Review (rev-capture).
        if let voiceEndObserver { NotificationCenter.default.removeObserver(voiceEndObserver) }
        voiceEndObserver = nil
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

    /// Width / height of the shape it was recorded in (C.5): the middle of the main frame, as the camera showed it.
    var aspectRatio: CGFloat {
        capture.format.aspectRatio
    }

    /// First frames for the still view. The selfie is taken where it lines up with the main frame's start.
    func load() async {
        main = await Self.still(capture.mainURL, maxPixelSize: 2048, at: 0)
        if let selfieURL = capture.selfieURL {
            selfie = await Self.still(selfieURL, maxPixelSize: 600, at: max(0, -(video?.selfieOffset ?? 0)))
        }
    }

    /// Plays a video on the card from the start, with sound, once both streams are ready.
    func startPlayback() async {
        guard let video, playback == nil else { return }
        let player = ViewerVideoPlayer(duration: video.duration)
        playback = player
        let main = AVURLAsset(url: video.mainURL)
        var selfie: AVPlayerItem?
        if let selfieURL = video.selfieURL, let duration = try? await main.load(.duration),
           let stream = try? await VideoComposer.selfieStream(selfieURL, offset: video.selfieOffset, mainDuration: duration) {
            selfie = AVPlayerItem(asset: stream)
        }
        // The voice note pauses whenever the video starts, however it was started.
        player.willPlay = { [weak self] in self?.pauseVoice() }
        await player.load(main: AVPlayerItem(asset: main), selfie: selfie)
        // Saved or retaken meanwhile: this player is done with.
        guard playback === player else { return player.stop() }
        // Not over a voice note playing or being recorded: its audio session stays as it is.
        guard !playsVoice, voiceRecording?.isFinished != false else { return }
        player.play()
    }

    func stopPlayback() {
        playback?.stop()
        playback = nil
    }

    /// What Save keeps.
    var momentDraft: MomentDraft {
        MomentDraft(
            capture: capture, caption: caption, note: note, window: hasSelfie ? windowFrame : nil, promptID: promptID, voice: voice,
            place: place, repeatOf: repeatOf, tags: tags, mood: mood, momentID: momentID
        )
    }

    /// Retake / Record again: nothing is kept.
    func discard() {
        isFinished = true
        stopPlayback()
        removeVoice()
        capture.discardFiles()
        drafts?.clear()
    }

    /// What a saved video needs to play composed again.
    func timing(_ video: CapturedVideo) -> VideoTiming {
        VideoTiming(
            duration: video.duration, selfieOffset: video.selfieOffset, hasAudio: video.hasAudio,
            mainPosition: video.mainPosition, window: video.selfieURL == nil ? nil : windowFrame,
            halves: capture.isHalves ? capture.format : nil
        )
    }

    /// An upright still of a photo, or of a video at `seconds`.
    nonisolated static func still(_ url: URL, maxPixelSize: Int, at seconds: TimeInterval) async -> UIImage? {
        if let image = await ImageDecoding.thumbnail(url, maxPixelSize: maxPixelSize) {
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
