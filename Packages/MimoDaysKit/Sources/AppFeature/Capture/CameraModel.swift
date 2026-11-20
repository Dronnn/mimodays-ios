import Core
import Foundation
import OSLog
import Observation
import Persistence

/// What the camera hands on to review (C07).
struct CaptureResult: Codable, Equatable, Sendable {
    enum Media: Codable, Equatable, Sendable {
        case photo(CapturedPhoto)
        case video(CapturedVideo)
    }

    var media: Media
    /// The selfie window's corner and size at capture; nil without a selfie. Review can still move it, and the
    /// composed preview is made at save with where it ends up (Andrew, 2026-11-13).
    var window: CameraSettings.SelfieWindow?
    var capturedAt: CaptureTime
    /// U01: the format it was recorded in.
    var format = CaptureFormat.portrait
    /// H.8: halves when the two cameras shared the frame; nil is the window.
    var arrangement: PiPLayout.Arrangement?

    /// Both cameras in halves: only with a selfie, and never on 1:1.
    var isHalves: Bool { arrangement == .halves && selfieURL != nil && format != .square }

    var mainURL: URL {
        switch media {
        case let .photo(photo): photo.mainURL
        case let .video(video): video.mainURL
        }
    }

    var selfieURL: URL? {
        switch media {
        case let .photo(photo): photo.selfieURL
        case let .video(video): video.selfieURL
        }
    }

    /// Removes the temporary files of a capture nobody keeps.
    func discardFiles() {
        [mainURL, selfieURL].compactMap(\.self).forEach { try? FileManager.default.removeItem(at: $0) }
    }
}

/// A capture that didn't work, for the C13 note.
enum CaptureFailure: Equatable {
    case lowStorage
    case failed

    init(_ error: any Error) {
        self = error as? CaptureError == .lowStorage ? .lowStorage : .failed
    }
}

/// The camera's C13 note (Andrew approved the copy for the undesigned ones, 2026-11-13).
enum CameraNotice: Equatable {
    /// C13b: video with sound on, microphone denied in Settings.
    case microphoneOff
    case lowStorage
    case interrupted(CaptureInterruption)
    /// The camera couldn't start.
    case unavailable
    /// A capture failed or its file was unreadable; nothing was kept.
    case captureFailed
}

/// The camera screen's state (C01-C05): engine setup, mode, controls and recording.
@MainActor
@Observable
final class CameraModel {
    private static let logger = Logger(subsystem: "MimoDays", category: "Camera")

    enum Phase: Equatable {
        case starting
        case ready
        /// A photo is being taken.
        case busy
        /// Nil from the shutter until the files are being written: only then do the timer and its pill show.
        case recording(startedAt: Date?)
        case failed(CaptureError)
    }

    /// Set by the model; tests set it directly to show a state.
    var phase = Phase.starting
    private(set) var setup: CameraSetup?
    var mode: CameraSettings.Mode {
        didSet { if mode != oldValue { Task { await refreshMicrophone() } } }
    }
    /// The last torch change asked for; each waits for the one before, so they reach the camera in order.
    private var torch: Task<Void, Never>?
    /// The selfie window is shown and captured (dual setups only).
    private(set) var showsSelfie = true
    /// The rear lenses the ••• sheet offers; one means no choice.
    private(set) var lenses: [BackLens] = []
    /// Dual setups: the front camera is the big one (↻).
    private(set) var isSwapped = false
    /// A call, the background or heat has the camera; nothing can be captured until it's back.
    private(set) var interruption: CaptureInterruption?
    /// C05 note, shown until the person flips or captures.
    private(set) var showsSingleCameraNote = false
    /// How the phone is held (U01-U07).
    private(set) var hold = DeviceHold.upright
    /// The hold a recording started in; the layout keeps it until the recording ends (U05).
    private(set) var recordingHold: DeviceHold?
    var settings: CameraSettings {
        didSet {
            store.save(settings)
            if settings.recordsSound != oldValue.recordsSound { Task { await refreshMicrophone() } }
            if isRecording, settings.flash != oldValue.flash { setTorch(settings.flash) }
            if settings.backLens != oldValue.backLens, phase != .starting {
                Task { [engine, lens = settings.backLens] in try? await engine.setBackLens(lens) }
            }
        }
    }

    let isSurprise: Bool
    let engine: any CaptureEngine
    private let orientation: any OrientationSensor
    private var holds: Task<Void, Never>?
    /// How many setup changes the engine has reported.
    private var setupChanges = 0

    /// The event listener lives as long as the model; it ends with it.
    isolated deinit {
        events?.cancel()
        holds?.cancel()
    }
    private let store: any CameraSettingsStore
    private let clock: any DateProvider
    private let microphoneStatus: @MainActor () async -> PermissionStatus
    private let onCapture: @MainActor (CaptureResult) -> Void
    private var events: Task<Void, Never>?

    init(
        engine: any CaptureEngine, store: any CameraSettingsStore, isSurprise: Bool,
        orientation: any OrientationSensor = FixedOrientationSensor(),
        clock: any DateProvider = SystemDateProvider(),
        microphoneStatus: @escaping @MainActor () async -> PermissionStatus,
        onCapture: @escaping @MainActor (CaptureResult) -> Void
    ) {
        self.engine = engine
        self.orientation = orientation
        self.store = store
        self.isSurprise = isSurprise
        self.clock = clock
        self.microphoneStatus = microphoneStatus
        self.onCapture = onCapture
        let settings = store.load()
        self.settings = settings
        mode = settings.opensIn
    }

    // MARK: Cameras

    var mainPosition: CameraPosition {
        switch setup {
        case let .single(position): position
        case .dual: isSwapped ? .front : .back
        case nil: .back
        }
    }

    /// The camera in the selfie window, if one is shown.
    var selfiePosition: CameraPosition? {
        setup == .dual && showsSelfie ? mainPosition.other : nil
    }

    var canToggleSelfie: Bool { setup == .dual }

    /// The shutter works: the camera is idle, not interrupted, and held the way the format needs.
    var canCapture: Bool { phase == .ready && interruption == nil && formatFitsHold }

    var format: CaptureFormat { settings.format }

    /// H.8: the two cameras each fill half the frame: picked in the ••• sheet, with both cameras, not on 1:1.
    var showsHalves: Bool { settings.arrangement == .halves && selfiePosition != nil && format != .square }

    /// 16:9 needs the phone on its side; 9:16 and 1:1 need it upright (U03, U06).
    var formatFitsHold: Bool { format == .landscape ? hold.isLandscape : !hold.isLandscape }

    /// U03/U06: the rotate hint, while the phone is held the wrong way and nothing is recording.
    var needsRotation: Bool { !formatFitsHold && !isRecording }

    /// The hold the screen is laid out for: the recording's while one runs.
    var layoutHold: DeviceHold { recordingHold ?? hold }

    /// U01: changes the format; it stays fixed while recording (U05).
    func setFormat(_ format: CaptureFormat) {
        guard !isRecording, phase != .busy else { return }
        settings.format = format
    }

    var isRecording: Bool {
        if case .recording = phase { true } else { false }
    }

    /// The files are being written (the shutter was pressed a moment before).
    var recordingHasBegun: Bool {
        if case .recording(startedAt: _?) = phase { true } else { false }
    }

    /// When the shutter started the current recording; for the log of how long the cameras took to begin.
    private var shutterAt: Date?
    /// The length chosen at the shutter, which the recording, its timer and its ring keep.
    private(set) var recordingLength = CameraSettings.VideoLength.short

    var microphoneOn: Bool { settings.recordsSound && microphone.isUsable }
    private(set) var microphone = PermissionStatus.notDetermined
    /// The last capture that didn't work; cleared by the next try.
    private(set) var failure: CaptureFailure?

    /// What the C13 note says, most important first. Nil while recording.
    var notice: CameraNotice? {
        if isRecording { return nil }
        if case .failed = phase { return .unavailable }
        if let interruption { return .interrupted(interruption) }
        if let failure { return failure == .lowStorage ? .lowStorage : .captureFailed }
        if mode == .video, settings.recordsSound, microphone.needsSettings { return .microphoneOff }
        return nil
    }

    func start() async {
        // One listener for the model's life, from its first start: a call ending while Review shows still arrives,
        // and a second start (Retake, the screen appearing again) doesn't drop what came before.
        // Set up before the first wait, so two starts overlapping can't both subscribe.
        if events == nil { listenForEvents(engine.events) }
        isClosed = false
        do {
            try? await engine.setBackLens(settings.backLens)
            // A setup change reported while starting (heat dropped the selfie camera) is newer than what start saw.
            let changes = setupChanges
            let started = try await engine.start()
            // Closed while the camera was starting: its stop ran first, so the camera goes off again.
            guard !isClosed else {
                await engine.stop()
                return
            }
            if setupChanges == changes { setup = started }
            lenses = await engine.backLenses()
            showsSingleCameraNote = setup != .dual
            phase = .ready
            await refreshMicrophone()
            listenForHolds()
        } catch {
            phase = .failed(error as? CaptureError ?? .cameraUnavailable)
        }
    }

    /// Back in the app with the camera still stopped by an error: it's started again, so the shutter doesn't stay off
    /// until the camera is closed and reopened. A call or another app ending sends its own "resumed".
    func recover() async {
        guard interruption == .other, phase == .ready, !isClosed else { return }
        _ = try? await engine.start()
    }

    /// The camera screen went away (closed, or Review took its place): a photo or clip still finishing is thrown
    /// away instead of opening a review nobody sees, which would come back at the next launch.
    func close() {
        isClosed = true
        Task { await stop() }
    }

    private var isClosed = false

    func stop() async {
        holds?.cancel()
        holds = nil
        if isRecording { await engine.stopRecording() }
        await engine.stop()
    }

    /// ↻: swaps the big camera on dual setups, switches cameras on single ones.
    func flip() async {
        guard phase == .ready else { return }
        showsSingleCameraNote = false
        if setup == .dual {
            isSwapped.toggle()
        } else if let flipped = try? await engine.flip() {
            setup = flipped
        }
    }

    func toggleSelfie() {
        guard canToggleSelfie, !isRecording else { return }
        showsSelfie.toggle()
    }

    func toggleSound() {
        settings.recordsSound.toggle()
    }

    // MARK: Capture

    /// Shutter: a photo, or start/stop a video.
    func shutter() async {
        switch (mode, phase) {
        case (.photo, .ready) where canCapture: await takePhoto()
        case (.video, .ready) where canCapture: await record()
        case (.video, .recording):
            // Stop can come while the recording is still starting (torch, microphone): it's kept for it.
            stopsRecording = true
            await engine.stopRecording()
        default: break
        }
    }

    /// Stop was tapped for the recording now starting or running.
    private var stopsRecording = false

    private func takePhoto() async {
        phase = .busy
        showsSingleCameraNote = false
        failure = nil
        do {
            let capturedAt = now
            let shot = shot
            await engine.setCaptureHold(hold)
            let captured = arranged(try await engine.capturePhoto(flash: settings.flash, silent: !settings.cameraSounds), as: shot)
            guard let photo = MediaCheck.checked(captured) else { throw CaptureError.photoFailed }
            phase = .ready
            deliver(result(.photo(photo), selfie: photo.selfieURL, at: capturedAt, as: shot))
        } catch {
            phase = .ready
            failure = CaptureFailure(error)
        }
    }

    private func record() async {
        let capturedAt = now
        // The big camera as it was at the shutter: heat dropping the front camera as the clip ends resets the swap.
        let shot = shot
        // The length chosen at the shutter, not one picked while the torch and microphone start.
        recordingLength = settings.videoLength
        let limit = recordingLength.duration
        phase = .recording(startedAt: nil)
        stopsRecording = false
        shutterAt = Date()
        recordingHold = hold
        defer { recordingHold = nil }
        await engine.setCaptureHold(hold)
        showsSingleCameraNote = false
        failure = nil
        if settings.flash != .off { await setTorch(settings.flash).value }
        // The sound setting as it is at the shutter, whatever an earlier change left behind.
        try? await engine.setMicrophone(microphoneOn)
        // Stopped before anything was recorded: no clip, and no recording running on to its limit.
        guard !stopsRecording else {
            await setTorch(.off).value
            phase = .ready
            return
        }
        do {
            let recorded = arranged(try await engine.record(limit: limit), as: shot)
            await setTorch(.off).value
            guard let video = await MediaCheck.checked(recorded) else { throw CaptureError.recordingFailed }
            phase = .ready
            deliver(result(.video(video), selfie: video.selfieURL, at: capturedAt, as: shot))
        } catch {
            await setTorch(.off).value
            phase = .ready
            failure = CaptureFailure(error)
        }
    }

    private func deliver(_ capture: CaptureResult) {
        guard !isClosed else {
            capture.discardFiles()
            return
        }
        onCapture(capture)
    }

    /// The flash button: off, auto, on, round again.
    func nextFlash() {
        let all = FlashMode.allCases
        settings.flash = all[(all.firstIndex(of: settings.flash)! + 1) % all.count]
    }

    @discardableResult
    private func setTorch(_ mode: FlashMode) -> Task<Void, Never> {
        let previous = torch
        let engine = engine
        let task = Task {
            await previous?.value
            await engine.setTorch(mode)
        }
        torch = task
        return task
    }

    /// What the screen showed at the shutter. A photo finishes after the flash and a clip after Stop: a format,
    /// window or Halves change made meanwhile is for the next one, not this.
    private struct Shot {
        var swapped: Bool
        var showsSelfie: Bool
        var halves: Bool
        var format: CaptureFormat
        var window: CameraSettings.SelfieWindow
    }

    private var shot: Shot {
        Shot(swapped: isSwapped, showsSelfie: showsSelfie, halves: showsHalves, format: format, window: settings.selfieWindow)
    }

    /// Big camera first; a hidden selfie window is never kept.
    private func arranged(_ photo: CapturedPhoto, as shot: Shot) -> CapturedPhoto {
        var photo = photo
        if shot.swapped, let selfie = photo.selfieURL {
            photo = CapturedPhoto(mainURL: selfie, mainPosition: photo.mainPosition.other, selfieURL: photo.mainURL)
        }
        if !shot.showsSelfie, let selfie = photo.selfieURL {
            try? FileManager.default.removeItem(at: selfie)
            photo.selfieURL = nil
        }
        return photo
    }

    private var now: CaptureTime { CaptureTime(instant: clock.now(), timeZone: .current) }

    private func result(_ media: CaptureResult.Media, selfie: URL?, at time: CaptureTime, as shot: Shot) -> CaptureResult {
        CaptureResult(
            media: media, window: selfie == nil ? nil : shot.window, capturedAt: time, format: shot.format,
            arrangement: selfie != nil && shot.halves ? .halves : nil
        )
    }

    private func arranged(_ video: CapturedVideo, as shot: Shot) -> CapturedVideo {
        var video = video
        if shot.swapped, let selfie = video.selfieURL {
            video.selfieURL = video.mainURL
            video.mainURL = selfie
            video.mainPosition = video.mainPosition.other
            video.selfieOffset = -video.selfieOffset
        }
        if !shot.showsSelfie, let selfie = video.selfieURL {
            try? FileManager.default.removeItem(at: selfie)
            video.selfieURL = nil
            video.selfieOffset = 0
        }
        return video
    }

    // MARK: Engine

    /// The microphone runs only in video mode, with permission and "Record sound" on. Also called after the
    /// microphone permission is answered (C06c).
    func refreshMicrophone() async {
        guard phase != .starting else { return }
        microphone = await microphoneStatus()
        try? await engine.setMicrophone(mode == .video && microphoneOn)
    }

    private func listenForHolds() {
        let stream = orientation.holds
        holds = Task { [weak self] in
            for await hold in stream {
                guard let self else { return }
                self.hold = hold
            }
        }
    }

    private func listenForEvents(_ stream: AsyncStream<CaptureEvent>) {
        events = Task { [weak self] in
            for await event in stream {
                guard let self else { return }
                switch event {
                case let .setupChanged(setup):
                    self.setup = setup
                    setupChanges += 1
                    if setup != .dual { isSwapped = false }
                case let .interrupted(reason):
                    interruption = reason
                case .resumed:
                    interruption = nil
                case .recordingStarted:
                    guard case let .recording(startedAt) = phase, startedAt == nil else { break }
                    let now = Date()
                    if let shutterAt { Self.logger.info("Recording began \(Int(now.timeIntervalSince(shutterAt) * 1000), privacy: .public) ms after the shutter") }
                    phase = .recording(startedAt: now)
                }
            }
        }
    }
}
