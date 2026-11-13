import Core
import Foundation
import Observation

/// What the camera hands on: Review (C07) takes it from here.
enum CaptureResult: Equatable, Sendable {
    case photo(CapturedPhoto)
    case video(CapturedVideo)
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
        didSet { if mode != oldValue { Task { await updateMicrophone() } } }
    }
    var isFlashOn = false
    /// The selfie window is shown and captured (dual setups only).
    private(set) var showsSelfie = true
    /// Dual setups: the front camera is the big one (↻).
    private(set) var isSwapped = false
    /// C05 note, shown until the person flips or captures.
    private(set) var showsSingleCameraNote = false
    var settings: CameraSettings {
        didSet { store.save(settings) }
    }

    let isSurprise: Bool
    let engine: any CaptureEngine
    private let store: any CameraSettingsStore
    private let clock: any DateProvider
    private let microphoneAllowed: @MainActor () async -> Bool
    private let onCapture: @MainActor (CaptureResult) -> Void
    private var events: Task<Void, Never>?

    init(
        engine: any CaptureEngine, store: any CameraSettingsStore, isSurprise: Bool,
        clock: any DateProvider = SystemDateProvider(),
        microphoneAllowed: @escaping @MainActor () async -> Bool,
        onCapture: @escaping @MainActor (CaptureResult) -> Void
    ) {
        self.engine = engine
        self.store = store
        self.isSurprise = isSurprise
        self.clock = clock
        self.microphoneAllowed = microphoneAllowed
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

    var isRecording: Bool {
        if case .recording = phase { true } else { false }
    }

    var microphoneOn: Bool { settings.recordsSound && microphoneAvailable }
    private(set) var microphoneAvailable = false

    func start() async {
        do {
            setup = try await engine.start()
            showsSingleCameraNote = setup != .dual
            phase = .ready
            await updateMicrophone()
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

    func toggleSound() async {
        settings.recordsSound.toggle()
        await updateMicrophone()
    }

    // MARK: Capture

    /// Shutter: a photo, or start/stop a video.
    func shutter() async {
        switch (mode, phase) {
        case (.photo, .ready): await takePhoto()
        case (.video, .ready): await record()
        case (.video, .recording): await engine.stopRecording()
        default: break
        }
    }

    private func takePhoto() async {
        phase = .busy
        showsSingleCameraNote = false
        do {
            let photo = try await engine.capturePhoto(flash: isFlashOn, silent: !settings.cameraSounds)
            phase = .ready
            onCapture(.photo(arranged(photo)))
        } catch {
            phase = .ready
        }
    }

    private func record() async {
        phase = .recording(startedAt: clock.now())
        showsSingleCameraNote = false
        do {
            let video = try await engine.record(limit: settings.videoLength.duration)
            phase = .ready
            onCapture(.video(arranged(video)))
        } catch {
            phase = .ready
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

    /// The microphone runs only in video mode, with permission and "Record sound" on.
    private func updateMicrophone() async {
        guard phase != .starting else { return }
        microphoneAvailable = await microphoneAllowed()
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
                }
            }
        }
    }
}
