import Core
import Foundation
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
    enum Phase: Equatable {
        case starting
        case ready
        /// A photo is being taken.
        case busy
        case recording(startedAt: Date)
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
        // This start's events, from its first moment; what was interrupted before (a retake) is news no more.
        let events = engine.events
        interruption = nil
        do {
            try? await engine.setBackLens(settings.backLens)
            setup = try await engine.start()
            lenses = await engine.backLenses()
            showsSingleCameraNote = setup != .dual
            phase = .ready
            await refreshMicrophone()
            listenForEvents(events)
            listenForHolds()
        } catch {
            phase = .failed(error as? CaptureError ?? .cameraUnavailable)
        }
    }

    func stop() async {
        events?.cancel()
        events = nil
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
        case (.video, .recording): await engine.stopRecording()
        default: break
        }
    }

    private func takePhoto() async {
        phase = .busy
        showsSingleCameraNote = false
        failure = nil
        do {
            let capturedAt = now
            let swapped = isSwapped
            await engine.setCaptureHold(hold)
            let captured = arranged(try await engine.capturePhoto(flash: settings.flash, silent: !settings.cameraSounds), swapped: swapped)
            guard let photo = MediaCheck.checked(captured) else { throw CaptureError.photoFailed }
            phase = .ready
            onCapture(result(.photo(photo), selfie: photo.selfieURL, at: capturedAt))
        } catch {
            phase = .ready
            failure = CaptureFailure(error)
        }
    }

    private func record() async {
        let capturedAt = now
        // The big camera as it was at the shutter: heat dropping the front camera as the clip ends resets the swap.
        let swapped = isSwapped
        phase = .recording(startedAt: capturedAt.instant)
        recordingHold = hold
        defer { recordingHold = nil }
        await engine.setCaptureHold(hold)
        showsSingleCameraNote = false
        failure = nil
        if settings.flash != .off { await setTorch(settings.flash).value }
        // The sound setting as it is at the shutter, whatever an earlier change left behind.
        try? await engine.setMicrophone(microphoneOn)
        do {
            let recorded = arranged(try await engine.record(limit: settings.videoLength.duration), swapped: swapped)
            await setTorch(.off).value
            guard let video = await MediaCheck.checked(recorded) else { throw CaptureError.recordingFailed }
            phase = .ready
            onCapture(result(.video(video), selfie: video.selfieURL, at: capturedAt))
        } catch {
            await setTorch(.off).value
            phase = .ready
            failure = CaptureFailure(error)
        }
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

    /// Big camera first; a hidden selfie window is never kept.
    private func arranged(_ photo: CapturedPhoto, swapped: Bool) -> CapturedPhoto {
        var photo = photo
        if swapped, let selfie = photo.selfieURL {
            photo = CapturedPhoto(mainURL: selfie, mainPosition: photo.mainPosition.other, selfieURL: photo.mainURL)
        }
        if !showsSelfie, let selfie = photo.selfieURL {
            try? FileManager.default.removeItem(at: selfie)
            photo.selfieURL = nil
        }
        return photo
    }

    private var now: CaptureTime { CaptureTime(instant: clock.now(), timeZone: .current) }

    /// The window can't move while capturing, so the current placement is where it was.
    private func result(_ media: CaptureResult.Media, selfie: URL?, at time: CaptureTime) -> CaptureResult {
        CaptureResult(
            media: media, window: selfie == nil ? nil : settings.selfieWindow, capturedAt: time, format: format,
            arrangement: selfie != nil && showsHalves ? .halves : nil
        )
    }

    private func arranged(_ video: CapturedVideo, swapped: Bool) -> CapturedVideo {
        var video = video
        if swapped, let selfie = video.selfieURL {
            video.selfieURL = video.mainURL
            video.mainURL = selfie
            video.mainPosition = video.mainPosition.other
            video.selfieOffset = -video.selfieOffset
        }
        if !showsSelfie, let selfie = video.selfieURL {
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
        events?.cancel()
        events = Task { [weak self] in
            for await event in stream {
                guard let self else { return }
                switch event {
                case let .setupChanged(setup):
                    self.setup = setup
                    if setup != .dual { isSwapped = false }
                case let .interrupted(reason):
                    interruption = reason
                case .resumed:
                    interruption = nil
                }
            }
        }
    }
}
