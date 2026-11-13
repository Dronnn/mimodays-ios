import Core
import Foundation
import Observation

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
    var isFlashOn = false
    /// The selfie window is shown and captured (dual setups only).
    private(set) var showsSelfie = true
    /// Dual setups: the front camera is the big one (↻).
    private(set) var isSwapped = false
    /// A call, the background or heat has the camera; nothing can be captured until it's back.
    private(set) var interruption: CaptureInterruption?
    /// C05 note, shown until the person flips or captures.
    private(set) var showsSingleCameraNote = false
    var settings: CameraSettings {
        didSet {
            store.save(settings)
            if settings.recordsSound != oldValue.recordsSound { Task { await refreshMicrophone() } }
        }
    }

    let isSurprise: Bool
    let engine: any CaptureEngine
    private let store: any CameraSettingsStore
    private let clock: any DateProvider
    private let microphoneStatus: @MainActor () async -> PermissionStatus
    private let onCapture: @MainActor (CaptureResult) -> Void
    private var events: Task<Void, Never>?

    init(
        engine: any CaptureEngine, store: any CameraSettingsStore, isSurprise: Bool,
        clock: any DateProvider = SystemDateProvider(),
        microphoneStatus: @escaping @MainActor () async -> PermissionStatus,
        onCapture: @escaping @MainActor (CaptureResult) -> Void
    ) {
        self.engine = engine
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

    /// The shutter works: the camera is idle and not interrupted.
    var canCapture: Bool { phase == .ready && interruption == nil }

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
        do {
            setup = try await engine.start()
            showsSingleCameraNote = setup != .dual
            phase = .ready
            await refreshMicrophone()
            listenForEvents()
        } catch {
            phase = .failed(error as? CaptureError ?? .cameraUnavailable)
        }
    }

    func stop() async {
        events?.cancel()
        events = nil
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
        case (.photo, .ready) where interruption == nil: await takePhoto()
        case (.video, .ready) where interruption == nil: await record()
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
            let captured = arranged(try await engine.capturePhoto(flash: isFlashOn, silent: !settings.cameraSounds))
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
        phase = .recording(startedAt: capturedAt.instant)
        showsSingleCameraNote = false
        failure = nil
        do {
            let recorded = arranged(try await engine.record(limit: settings.videoLength.duration))
            guard let video = await MediaCheck.checked(recorded) else { throw CaptureError.recordingFailed }
            phase = .ready
            onCapture(result(.video(video), selfie: video.selfieURL, at: capturedAt))
        } catch {
            phase = .ready
            failure = CaptureFailure(error)
        }
    }

    /// Big camera first; a hidden selfie window is never kept.
    private func arranged(_ photo: CapturedPhoto) -> CapturedPhoto {
        var photo = photo
        if isSwapped, let selfie = photo.selfieURL {
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
        CaptureResult(media: media, window: selfie == nil ? nil : settings.selfieWindow, capturedAt: time)
    }

    private func arranged(_ video: CapturedVideo) -> CapturedVideo {
        var video = video
        if isSwapped, let selfie = video.selfieURL {
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

    private func listenForEvents() {
        let stream = engine.events
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
