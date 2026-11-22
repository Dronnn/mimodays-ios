@preconcurrency import AVFoundation
import Core
import Foundation
import OSLog
import Persistence
import SwiftData

/// F06-F09: one project's edits. Every change is saved as it's made (11.9); Undo steps back through them;
/// the stage plays the movie as it stands.
@MainActor
@Observable
final class MovieEditorModel {
    enum Tool: Hashable, CaseIterable {
        case clips
        case shape
        /// F08's captions and U51's text cards ("Captions" became "Text").
        case text
        case audio
    }

    /// One place on the picture lane: a clip or a text card (U50).
    enum Item: Identifiable {
        case clip(MovieClip)
        case card(MovieTextCard)

        var id: PersistentIdentifier {
            switch self {
            case let .clip(clip): clip.persistentModelID
            case let .card(card): card.persistentModelID
            }
        }

        var clip: MovieClip? {
            if case let .clip(clip) = self { clip } else { nil }
        }

        var card: MovieTextCard? {
            if case let .card(card) = self { card } else { nil }
        }

        fileprivate func place(at position: Int) {
            switch self {
            case let .clip(clip): clip.position = position
            case let .card(card): card.position = position
            }
        }
    }

    /// One clip's edit decisions, as Undo puts them back.
    struct ClipState: Equatable {
        var momentID: UUID
        var position: Int
        var trimStart: Double?
        var trimEnd: Double?
        var crop: NormalizedRect?
        var selfiePlacement: MovieSelfiePlacement?
        var transition: MovieTransition
        var clipAudio: ClipAudio
        var clipVolume: Double
        var includesVoiceNote: Bool
        var cameraLayout: ClipCameraLayout?
        var pipFrame: PiPLayout?
        var atmosphere: MovieAtmosphere?
    }

    /// One text card, as Undo puts it back.
    struct CardState: Equatable {
        var id: UUID
        var position: Int
        var text: String
        var look: TextCardLook
        var duration: Double
        var transition: MovieTransition
        var atmosphere: MovieAtmosphere?
        var voiceNoteID: UUID?
    }

    /// The whole project's edit decisions at one moment.
    struct Snapshot: Equatable {
        var title: String
        var aspectRatio: MovieAspectRatio
        var fit: MovieFit
        var showsDates: Bool
        var showsPlaces: Bool
        var showsTitle: Bool
        var clipSoundLevel: Double
        var voiceNoteLevel: Double
        var track: Track?
        var clips: [ClipState]
        var cards: [CardState]
    }

    /// The movie's one track: the person's music or their voice (F09).
    struct Track: Equatable {
        var kind: AudioTrackKind
        var relativePath: String
        var name: String?
        var gain: Double
        /// Seconds into the movie where it starts: a voice recorded as the movie played.
        var startOffset = 0.0
    }

    let project: MovieProject
    let tiles: MemoriesModel
    var tool: Tool = .clips
    /// The clips and text cards as the movie plays them, and what the composer made of each (same order).
    private(set) var items: [Item] = []
    private(set) var plan: MoviePlan
    private(set) var selected = 0
    private(set) var canUndo = false
    let player = AVPlayer()
    private(set) var time: Double = 0
    private(set) var isPlaying = false
    /// The composer couldn't make the movie (a clip's file is unreadable); the stage says so.
    private(set) var failed = false
    private let library: MediaLibrary
    private let clock: any DateProvider
    private let voice: VoiceServices
    private var undoStack: [Snapshot] = []
    private var rebuild: Task<Void, Never>?
    private var timeObserver: Any?
    /// Every music or voice file this editor has seen; the ones nothing points at go when it closes.
    private var audioFiles: Set<String> = []
    /// The audio session as it was before the microphone took it, so playback goes back to headphones after.
    private var playbackSession: (category: AVAudioSession.Category, mode: AVAudioSession.Mode)?
    private let logger = Logger(subsystem: "MimoDays", category: "Movies")
    /// Undo keeps this many steps.
    static let undoLimit = 50
    /// The stage is drawn at 720p; the export renders at the chosen quality.
    static let previewResolution = MovieResolution.p720
    /// Music sits under the clips' own sound and the voice notes.
    static let musicGain = 0.8
    /// The voice over the movie starts as loud as the voice notes; its slider sets it after.
    static let voiceoverGain = 1.0
    /// A shorter voice over the movie is dropped, as a voice note is.
    static let shortestVoiceover = 0.5

    init(project: MovieProject, library: MediaLibrary, clock: any DateProvider = SystemDateProvider(), voice: VoiceServices = .simulated) {
        self.project = project
        self.library = library
        self.clock = clock
        self.voice = voice
        tiles = MemoriesModel(context: library.context, store: library.store, thumbnails: library.thumbnails, clock: clock)
        plan = MoviePlan(clips: [], aspectRatio: project.aspectRatio, fit: project.fit)
        audioFiles = Set(project.audioTracks.map(\.relativePath))
        reload()
        observeTime()
    }

    /// The playhead follows playback; again after Export was pushed over the editor and popped (which closed it),
    /// when the stage is built again if closing stopped that half way (a change made just before).
    func observeTime() {
        guard timeObserver == nil else { return }
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 30), queue: .main) { [weak self] time in
            MainActor.assumeIsolated { self?.tick(time.seconds) }
        }
        if rebuild?.isCancelled == true { reload() }
    }

    private var store: MovieStore { MovieStore(context: library.context, store: library.store, now: { [clock] in clock.now() }) }

    // MARK: Timeline

    var duration: Double { plan.duration }

    /// Where each item starts in the movie.
    var starts: [Double] {
        var cursor = 0.0
        return plan.clips.map { clip in
            defer { cursor += clip.duration }
            return cursor
        }
    }

    /// The clip playing at `time`, and how far into it (0...1).
    var playhead: (index: Int, fraction: Double)? {
        guard !plan.clips.isEmpty else { return nil }
        let starts = starts
        let index = starts.lastIndex { $0 <= time + 0.0001 } ?? 0
        let length = plan.clips[index].duration
        return (index, length > 0 ? min(max((time - starts[index]) / length, 0), 1) : 0)
    }

    var selectedItem: Item? { items.indices.contains(selected) ? items[selected] : nil }
    var selectedClip: MovieClip? { selectedItem?.clip }
    var selectedCard: MovieTextCard? { selectedItem?.card }
    var selectedPlan: MoviePlan.Clip? { plan.clips.indices.contains(selected) ? plan.clips[selected] : nil }
    /// The clips alone, in play order.
    var clips: [MovieClip] { items.compactMap(\.clip) }
    /// How many items are clips ("Clip 3 of 24").
    var clipCount: Int { clips.count }

    func select(_ index: Int) {
        guard items.indices.contains(index) else { return }
        selected = index
        seek(to: starts[index])
    }

    // MARK: Playback

    func togglePlay() {
        if isPlaying {
            player.pause()
        } else {
            if time >= duration - 0.05 { seek(to: 0) }
            player.play()
        }
        isPlaying.toggle()
    }

    func pause() {
        player.pause()
        isPlaying = false
    }

    /// The preview played the same player; the editor picks up where it stopped, on the clip there, so Trim or
    /// Remove act on what was last seen.
    func caughtUp() {
        pause()
        seek(to: player.currentTime().seconds.isFinite ? player.currentTime().seconds : time)
        if let index = playhead?.index { selected = index }
    }

    func seek(to seconds: Double) {
        time = min(max(seconds, 0), duration)
        player.seek(to: CMTime(seconds: time, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func tick(_ seconds: Double) {
        guard isPlaying, seconds.isFinite else { return }
        time = seconds
        if let index = playhead?.index, index != selected { selected = index }
        if seconds >= duration - 0.02 {
            isPlaying = false
        }
    }

    // MARK: Clips (F06)

    /// A movie keeps one clip at least; a card can always go.
    var canRemove: Bool { selectedCard != nil || clipCount > 1 }

    func remove() {
        guard canRemove, let item = selectedItem else { return }
        edit {
            switch item {
            case let .clip(clip): library.context.delete(clip)
            case let .card(card): library.context.delete(card)
            }
            renumber(items.filter { $0.id != item.id })
        }
        selected = min(selected, items.count - 1)
    }

    /// Long-press and drag: the item at `source` goes to `destination`.
    func move(from source: Int, to destination: Int) {
        guard source != destination, items.indices.contains(source), items.indices.contains(destination) else { return }
        edit {
            var order = items
            order.insert(order.remove(at: source), at: destination)
            renumber(order)
        }
        selected = destination
    }

    /// How the item at `index` comes in after the one before (the dot between them, U53).
    func transition(at index: Int) -> MovieTransition {
        switch items.indices.contains(index) ? items[index] : nil {
        case let .clip(clip): clip.transition
        case let .card(card): card.transition
        case nil: .cut
        }
    }

    func atmosphere(at index: Int) -> MovieAtmosphere {
        switch items.indices.contains(index) ? items[index] : nil {
        case let .clip(clip): clip.atmosphere ?? MovieAtmosphere()
        case let .card(card): card.atmosphere ?? MovieAtmosphere()
        case nil: MovieAtmosphere()
        }
    }

    func setTransition(_ transition: MovieTransition, at index: Int? = nil) {
        let index = index ?? selected
        guard items.indices.contains(index), self.transition(at: index) != transition else { return }
        edit {
            switch items[index] {
            case let .clip(clip): clip.transition = transition
            case let .card(card): card.transition = transition
            }
        }
    }

    /// U53: how long the sound leads, and which sound.
    func setAtmosphere(_ atmosphere: MovieAtmosphere, at index: Int) {
        guard items.indices.contains(index), self.atmosphere(at: index) != atmosphere else { return }
        edit {
            switch items[index] {
            case let .clip(clip): clip.atmosphere = atmosphere
            case let .card(card): card.atmosphere = atmosphere
            }
        }
    }

    /// The selected clip shows another moment instead; its place in the movie and its transition stay.
    func replace(with momentID: UUID) {
        guard let clip = selectedClip,
              let moment = try? library.context.fetch(FetchDescriptor<Moment>(predicate: #Predicate { $0.id == momentID })).first
        else { return }
        edit {
            clip.moment = moment
            clip.trimStart = nil
            clip.trimEnd = nil
            clip.crop = nil
            clip.selfiePlacement = nil
        }
    }

    /// Video: the part from `start` to `end` seconds. Photo: shown for `end - start` seconds.
    func trim(start: Double, end: Double) {
        guard let clip = selectedClip, let media = selectedPlan?.media else { return }
        edit {
            switch media {
            case .photo:
                clip.trimStart = nil
                clip.trimEnd = end - start
            case .video:
                clip.trimStart = start
                clip.trimEnd = end
            case .card:
                break
            }
        }
    }

    /// The moments Replace offers: the source's, not already in the movie; every moment when the source has none.
    func replacements() -> [MemoryItem] {
        let used = Set(items.compactMap { $0.clip?.moment?.id })
        let source = NewMovieModel(library: library, source: project.sourceRule, clock: clock)
        _ = source.loadCandidates()
        var items = source.items.filter { !used.contains($0.id) }
        if items.isEmpty {
            let all = NewMovieModel(library: library, source: MovieSourceRule(kind: .selection), clock: clock)
            _ = all.loadCandidates()
            items = all.items.filter { !used.contains($0.id) }
        }
        return items
    }

    // MARK: Shape (F07)

    func setAspectRatio(_ ratio: MovieAspectRatio) {
        guard project.aspectRatio != ratio else { return }
        edit { project.aspectRatio = ratio }
    }

    func setFit(_ fit: MovieFit) {
        guard project.fit != fit else { return }
        edit { project.fit = fit }
    }

    func setPlacement(_ placement: MovieSelfiePlacement) {
        guard let clip = selectedClip, clip.selfiePlacement != placement else { return }
        edit { clip.selfiePlacement = placement }
    }

    // MARK: Cameras and sound (U52)

    /// Nil puts the cameras back as recorded.
    func setCameraLayout(_ layout: ClipCameraLayout?) {
        guard let clip = selectedClip, clip.cameraLayout != layout else { return }
        edit { clip.cameraLayout = layout }
    }

    /// The window dragged or pinched on the stage: where it goes, relative to the picture, and how big.
    func setWindow(_ frame: PiPLayout) {
        guard let clip = selectedClip, clip.pipFrame != frame else { return }
        edit {
            clip.pipFrame = frame
            // A window put somewhere by hand replaces F07's preset spot.
            clip.selfiePlacement = nil
            if clip.cameraLayout == nil { clip.cameraLayout = .window }
        }
    }

    func setClipSound(_ on: Bool) {
        guard let clip = selectedClip, (clip.clipAudio != .muted) != on else { return }
        edit { clip.clipAudio = on ? .original : .muted }
    }

    /// While the slider moves; `beginLevelChange` and `endLevelChange` make it one Undo step.
    func setClipVolume(_ volume: Double) { selectedClip?.clipVolume = min(max(volume, 0), 1) }

    func setIncludesVoiceNote(_ on: Bool) {
        guard let clip = selectedClip, clip.includesVoiceNote != on else { return }
        edit { clip.includesVoiceNote = on }
    }

    /// The selected clip's voice comment, if its moment has one.
    var selectedVoiceNote: MomentVoiceNote? { selectedClip?.moment?.voiceNotes.first }

    /// Seconds of voice comment over item `index` (the timeline's voice lane).
    func voiceLength(at index: Int) -> Double? {
        guard plan.clips.indices.contains(index), plan.clips[index].voiceURL != nil, items.indices.contains(index) else { return nil }
        switch items[index] {
        case let .clip(clip): return clip.moment?.voiceNotes.first?.duration
        case let .card(card): return voiceNotes.first { $0.id == card.voiceNoteID }?.duration
        }
    }

    /// "2" for the second clip, counting clips only.
    var selectedClipNumber: Int { items.prefix(selected + 1).count { $0.clip != nil } }

    /// "clip 2", "the text card" (U53's title).
    func itemName(_ index: Int) -> String {
        guard items.indices.contains(index) else { return String(appLocalized: "the start", bundle: .module, comment: "U53: before the first item") }
        if items[index].card != nil { return String(appLocalized: "the text card", bundle: .module, comment: "U53: a text card in the title") }
        let number = items.prefix(index + 1).count { $0.clip != nil }
        let format = String(appLocalized: "Transition title: clip %lld", defaultValue: "clip %lld", bundle: .module, comment: "U53: a clip in the transition sheet's title, e.g. clip 2")
        return String(format: format, number)
    }

    /// U54: while the playhead is in an Atmosphere lead, how far into it and how long it is.
    var leadProgress: (elapsed: Double, lead: Double)? {
        guard let playhead, plan.clips.indices.contains(playhead.index), let lead = plan.clips[playhead.index].lead else { return nil }
        let elapsed = playhead.fraction * plan.clips[playhead.index].duration
        return elapsed < lead ? (elapsed, lead) : nil
    }

    // MARK: Text cards (U51)

    /// A new card shows before the first clip; it can be dragged between clips afterwards.
    func addCard() {
        let card = MovieTextCard(project: project, position: 0, text: String(appLocalized: "A few words", bundle: .module, comment: "U51: a new text card's words, until they're changed"))
        edit {
            library.context.insert(card)
            renumber([.card(card)] + items)
        }
        selected = 0
        seek(to: 0)
    }

    /// Up to `cardLimit` characters, as drawn.
    static let cardLimit = 60
    static let cardDurations: [Double] = [2, 3, 5]

    func setCardText(_ text: String, of card: MovieTextCard) {
        let text = String(text.prefix(Self.cardLimit))
        guard !card.isDeleted, card.text != text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        edit { card.text = text }
    }

    func setCardLook(_ look: TextCardLook) {
        guard let card = selectedCard, card.look != look else { return }
        edit { card.look = look }
    }

    func setCardDuration(_ duration: Double) {
        guard let card = selectedCard, card.duration != duration else { return }
        edit { card.duration = duration }
    }

    /// Every voice comment of the movie's moments, newest first: what can play over a card.
    var voiceNotes: [MomentVoiceNote] {
        items.compactMap { $0.clip?.moment?.voiceNotes.first }.sorted { $0.recordedAt > $1.recordedAt }
    }

    /// Nil takes the voice off the card.
    func setCardVoice(_ note: MomentVoiceNote?) {
        guard let card = selectedCard, card.voiceNoteID != note?.id else { return }
        edit { card.voiceNoteID = note?.id }
    }

    /// Switching the voice on picks the comment of the clip after the card, else the newest one.
    func setCardHasVoice(_ on: Bool) {
        guard on else { return setCardVoice(nil) }
        let next = items.dropFirst(selected + 1).lazy.compactMap { $0.clip?.moment?.voiceNotes.first }.first
        setCardVoice(next ?? voiceNotes.first)
    }

    var selectedCardVoice: MomentVoiceNote? {
        guard let id = selectedCard?.voiceNoteID else { return nil }
        return voiceNotes.first { $0.id == id }
    }

    // MARK: Captions (F08)

    func setShowsDates(_ on: Bool) { edit { project.showsDates = on } }
    func setShowsPlaces(_ on: Bool) { edit { project.showsPlaces = on } }

    /// The title is the movie's name too; an empty one keeps the old name.
    func setTitle(_ title: String, shows: Bool) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        edit {
            if !title.isEmpty { project.title = title }
            project.showsTitle = shows
        }
    }

    // MARK: Audio (F09)

    /// Clips with a voice note of their own ("6 of 24 clips").
    var voiceNoteCount: Int { plan.clips.filter { !$0.isCard && $0.voiceURL != nil }.count }

    /// The movie's one track under everything: the person's music or their voice.
    var track: MovieAudioTrack? { project.audioTracks.first }

    /// A slider started moving: one Undo step for the whole drag.
    func beginLevelChange() { pushUndo() }

    /// While a slider moves the level changes at once; the movie is rebuilt when it stops.
    func setClipSoundLevel(_ level: Double) { project.clipSoundLevel = min(max(level, 0), 1) }
    func setVoiceNoteLevel(_ level: Double) { project.voiceNoteLevel = min(max(level, 0), 1) }
    func setTrackLevel(_ level: Double) { track?.gain = min(max(level, 0), 1) }

    func endLevelChange() { saved() }

    /// The person's own file (from Files) plays under the movie; it's copied in, so the original can go. A file
    /// that isn't readable audio is left out and the track stays as it was.
    func setMusic(from url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        guard Self.seconds(of: url) != nil else {
            logger.error("Adding music failed: the file isn't readable audio")
            return
        }
        do {
            let file = try library.store.store(copyOf: url, in: .originals, fileExtension: url.pathExtension.isEmpty ? nil : url.pathExtension)
            audioFiles.insert(file.relativePath)
            edit { put(Track(kind: .soundtrack, relativePath: file.relativePath, name: url.deletingPathExtension().lastPathComponent, gain: Self.musicGain)) }
        } catch {
            logger.error("Adding music failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// The file stays until the editor closes, so Undo can bring it back.
    func removeTrack() {
        guard track != nil else { return }
        edit { put(nil) }
    }

    /// The movie's track becomes `new`, or goes; the old one's file is left for `close`.
    private func put(_ new: Track?) {
        for track in project.audioTracks { library.context.delete(track) }
        guard let new else { return }
        let track = MovieAudioTrack(kind: new.kind, relativePath: new.relativePath, startOffset: new.startOffset, gain: new.gain)
        track.name = new.name
        track.project = project
        library.context.insert(track)
    }

    // MARK: Voice over the movie (F09)

    /// The take of the voice over the movie, from `newVoiceover` until it's finished; one at a time.
    private(set) var voiceover: VoiceRecording?
    /// Where the movie was when the take's microphone started.
    private var voiceoverStart = 0.0
    /// The movie's end finishes the take.
    private var voiceoverEnd: (any NSObjectProtocol)?

    /// A take getting ready: the stage stops and goes silent, so the movie's sound isn't recorded into the voice.
    /// Its sheet comes up at once and starts it (`startVoiceover`). Nil while another one is on.
    func newVoiceover() -> VoiceRecording? {
        guard voiceover == nil, duration > 0, let url = try? CaptureFiles.temporaryURL("m4a") else { return nil }
        let take = VoiceRecording(recorder: voice.makeRecorder(), url: url, limit: duration)
        voiceover = take
        voiceoverStart = 0
        pause()
        player.isMuted = true
        return take
    }

    /// Once the stage has caught up with every change and is ready at the start, the movie plays; the microphone starts
    /// as soon as it really moves, and records from there to the end, so the words stay with the pictures. False when
    /// it can't; nothing starts once the take was finished meanwhile (its sheet went away, the editor closed).
    func startVoiceover(_ take: VoiceRecording) async -> Bool {
        while let pending = rebuild, !pending.isCancelled { await pending.value }
        // Finished meanwhile: that put everything back already.
        guard voiceover === take else { return false }
        time = 0
        guard duration > 0, await wait(for: take, until: { player.currentItem?.status == .readyToPlay }),
              await player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero), voiceover === take
        else { return abandon(take) }
        selected = 0
        player.play()
        isPlaying = true
        guard await wait(for: take, until: { player.timeControlStatus == .playing }) else { return abandon(take) }
        // At most what's left of the movie; the movie's end stops it anyway.
        take.limit = duration - max(player.currentTime().seconds, 0)
        guard take.limit > 0 else { return abandon(take) }
        let session = AVAudioSession.sharedInstance()
        playbackSession = (session.category, session.mode)
        guard take.start() else {
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            return abandon(take)
        }
        // Where the movie is now the microphone has really started: the voice goes there. Already at its end, there's
        // nothing to record over.
        voiceoverStart = max(player.currentTime().seconds, 0)
        guard voiceoverStart < duration, let item = player.currentItem, !Self.atEnd(item) else { return abandon(take) }
        take.limit = duration - voiceoverStart
        voiceoverEnd = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.finishVoiceover(take) }
        }
        return true
    }

    private static func atEnd(_ item: AVPlayerItem) -> Bool {
        item.duration.isNumeric && item.currentTime() >= item.duration
    }

    private func stopWatchingTheEnd() {
        if let voiceoverEnd { NotificationCenter.default.removeObserver(voiceoverEnd) }
        voiceoverEnd = nil
    }

    /// Up to three seconds for `condition`; false at once when `take` is finished meanwhile or the stage failed.
    private func wait(for take: VoiceRecording, until condition: () -> Bool) async -> Bool {
        for _ in 0 ..< 100 {
            guard voiceover === take, !failed, player.currentItem?.status != .failed else { return false }
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(30))
        }
        return false
    }

    /// A take that couldn't start: everything as it was, nothing recorded.
    private func abandon(_ take: VoiceRecording) -> Bool {
        guard voiceover === take else { return false }
        voiceover = nil
        stopWatchingTheEnd()
        take.finish()
        pause()
        restorePlayback()
        try? FileManager.default.removeItem(at: take.url)
        return false
    }

    /// Stop, the movie's end, the sheet or the app left, the editor closed: what was recorded becomes the movie's
    /// track. Once per take, whichever comes first; a take that hadn't started yet leaves everything as it was.
    func finishVoiceover(_ take: VoiceRecording) {
        guard voiceover === take else { return }
        voiceover = nil
        stopWatchingTheEnd()
        take.finish()
        pause()
        restorePlayback()
        addVoiceover(at: take.url, startingAt: voiceoverStart)
    }

    private func restorePlayback() {
        player.isMuted = false
        guard let playbackSession else { return }
        try? AVAudioSession.sharedInstance().setCategory(playbackSession.category, mode: playbackSession.mode)
        self.playbackSession = nil
    }

    /// A recording replaces the music or an earlier voice; it's moved in, to play from `start` seconds into the movie.
    /// Too short (for a movie that short, shorter than what's left of it) or unreadable, it's dropped and the track
    /// stays as it was.
    func addVoiceover(at url: URL, startingAt start: Double = 0) {
        guard let seconds = Self.seconds(of: url), seconds >= min(Self.shortestVoiceover, duration - start) else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        do {
            let file = try library.store.store(moving: url, in: .originals, fileExtension: "m4a")
            audioFiles.insert(file.relativePath)
            edit { put(Track(kind: .voiceover, relativePath: file.relativePath, name: nil, gain: Self.voiceoverGain, startOffset: start)) }
        } catch {
            try? FileManager.default.removeItem(at: url)
            logger.error("Adding the voice failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func seconds(of url: URL) -> Double? {
        guard let file = try? AVAudioFile(forReading: url), file.length > 0 else { return nil }
        return Double(file.length) / file.processingFormat.sampleRate
    }

    // MARK: Undo

    func undo() {
        guard let snapshot = undoStack.popLast() else { return }
        apply(snapshot)
        canUndo = !undoStack.isEmpty
        saved()
    }

    var snapshot: Snapshot {
        Snapshot(
            title: project.title, aspectRatio: project.aspectRatio, fit: project.fit, showsDates: project.showsDates,
            showsPlaces: project.showsPlaces, showsTitle: project.showsTitle, clipSoundLevel: project.clipSoundLevel,
            voiceNoteLevel: project.voiceNoteLevel, track: track.map(Track.init),
            clips: project.orderedClips.compactMap { clip in
                clip.moment.map {
                    ClipState(
                        momentID: $0.id, position: clip.position, trimStart: clip.trimStart, trimEnd: clip.trimEnd, crop: clip.crop,
                        selfiePlacement: clip.selfiePlacement, transition: clip.transition, clipAudio: clip.clipAudio,
                        clipVolume: clip.clipVolume, includesVoiceNote: clip.includesVoiceNote, cameraLayout: clip.cameraLayout,
                        pipFrame: clip.pipFrame, atmosphere: clip.atmosphere
                    )
                }
            },
            cards: project.textCards.sorted { $0.position < $1.position }.map {
                CardState(
                    id: $0.id, position: $0.position, text: $0.text, look: $0.look, duration: $0.duration, transition: $0.transition,
                    atmosphere: $0.atmosphere, voiceNoteID: $0.voiceNoteID
                )
            }
        )
    }

    private func apply(_ snapshot: Snapshot) {
        project.title = snapshot.title
        project.aspectRatio = snapshot.aspectRatio
        project.fit = snapshot.fit
        project.showsDates = snapshot.showsDates
        project.showsPlaces = snapshot.showsPlaces
        project.showsTitle = snapshot.showsTitle
        project.clipSoundLevel = snapshot.clipSoundLevel
        project.voiceNoteLevel = snapshot.voiceNoteLevel
        if track.map(Track.init) != snapshot.track { put(snapshot.track) }
        if self.snapshot.clips != snapshot.clips {
            for clip in project.clips { library.context.delete(clip) }
            let ids = snapshot.clips.map(\.momentID)
            let moments = (try? library.context.fetch(FetchDescriptor<Moment>(predicate: #Predicate { ids.contains($0.id) }))) ?? []
            let byID = Dictionary(moments.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            for state in snapshot.clips {
                guard let moment = byID[state.momentID] else { continue }
                let clip = MovieClip(project: project, moment: moment, position: state.position)
                clip.trimStart = state.trimStart
                clip.trimEnd = state.trimEnd
                clip.crop = state.crop
                clip.selfiePlacement = state.selfiePlacement
                clip.transition = state.transition
                clip.clipAudio = state.clipAudio
                clip.clipVolume = state.clipVolume
                clip.includesVoiceNote = state.includesVoiceNote
                clip.cameraLayout = state.cameraLayout
                clip.pipFrame = state.pipFrame
                clip.atmosphere = state.atmosphere
                library.context.insert(clip)
            }
        }
        if self.snapshot.cards != snapshot.cards {
            for card in project.textCards { library.context.delete(card) }
            for state in snapshot.cards {
                let card = MovieTextCard(id: state.id, project: project, position: state.position, text: state.text, look: state.look, duration: state.duration)
                card.transition = state.transition
                card.atmosphere = state.atmosphere
                card.voiceNoteID = state.voiceNoteID
                library.context.insert(card)
            }
        }
    }

    private func pushUndo() {
        undoStack.append(snapshot)
        if undoStack.count > Self.undoLimit { undoStack.removeFirst() }
        canUndo = true
    }

    // MARK: Saving

    /// One Undo step: what the change was made on, the change, saved at once.
    private func edit(_ change: () -> Void) {
        pushUndo()
        change()
        saved()
    }

    private func renumber(_ order: [Item]) {
        for (position, item) in order.enumerated() { item.place(at: position) }
    }

    /// Autosave (11.9): every change is kept the moment it's made; the stage follows.
    private func saved() {
        project.updatedAt = clock.now()
        do {
            try library.context.save()
        } catch {
            logger.error("Saving the movie failed: \(error.localizedDescription, privacy: .public)")
        }
        reload()
    }

    /// rev-library: moments whose picture can't be read, left out here as the export leaves them out; each moment is
    /// checked once.
    private var unreadable: Set<UUID> = []
    private var checkedMoments: Set<UUID> = []

    /// Reads the clips back and rebuilds what the stage plays, keeping its place.
    func reload() {
        let full = MoviePlan(project, store: library.store)
        plan = full
        plan.clips.removeAll { !$0.isCard && unreadable.contains($0.momentID) }
        // The plan has the same order: each of its entries is a card by its id or the next clip of that moment.
        var clips = MovieStore.liveClips(of: project)
        let cards = Dictionary(project.textCards.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        items = plan.clips.compactMap { planned in
            if planned.isCard { return cards[planned.momentID].map(Item.card) }
            guard let index = clips.firstIndex(where: { $0.moment?.id == planned.momentID }) else { return nil }
            return .clip(clips.remove(at: index))
        }
        selected = min(selected, max(items.count - 1, 0))
        time = min(time, duration)
        let plan = plan
        rebuild?.cancel()
        rebuild = Task {
            let found = await full.unreadableMoments(skipping: checkedMoments)
            guard !Task.isCancelled else { return }
            checkedMoments.formUnion(full.clips.filter { !$0.isCard }.map(\.momentID))
            if !found.isEmpty {
                unreadable.formUnion(found)
                rebuild = nil
                return reload()
            }
            do {
                let composed = try await MovieComposer.compose(plan, renderSize: plan.aspectRatio.renderSize(Self.previewResolution))
                guard !Task.isCancelled else { return }
                failed = false
                player.replaceCurrentItem(with: composed.playerItem())
                await player.seek(to: CMTime(seconds: time, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
                if isPlaying { player.play() }
            } catch {
                guard !Task.isCancelled else { return }
                failed = true
                logger.error("Composing the movie failed: \(error.localizedDescription, privacy: .public)")
            }
            // Finished: only a rebuild `close` stopped is left behind, for `observeTime` to start again.
            if !Task.isCancelled { rebuild = nil }
        }
    }

    /// Waits for the stage to catch up with the last change (tests, export).
    func settled() async {
        // A build that found an unreadable clip starts the next one itself.
        while let task = rebuild {
            await task.value
            if rebuild == task { return }
        }
    }

    /// A take still on ends with it, kept as recorded. Music and voice files no project uses any more go when the
    /// editor closes. Ones Undo can still bring back stay: going to Export closes it too, and the editor is still there
    /// to come back to. The launch sweep takes them later.
    func close() {
        if let voiceover { finishVoiceover(voiceover) }
        pause()
        rebuild?.cancel()
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        store.removeUnusedAudio(audioFiles.subtracting(undoStack.compactMap(\.track?.relativePath)))
    }
}

private extension MovieEditorModel.Track {
    init(_ track: MovieAudioTrack) {
        self.init(kind: track.kind, relativePath: track.relativePath, name: track.name, gain: track.gain, startOffset: track.startOffset)
    }
}
