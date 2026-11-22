import AVFoundation
import QuartzCore
import Synchronization
import os

/// The device cameras. `AVCaptureMultiCamSession` with rear + front when supported, otherwise one
/// `AVCaptureSession` camera at a time. Each camera has its own photo and movie output (separate streams).
/// All session work runs on one serial queue. Interruptions (calls, background, heat) end a recording with
/// what it has; a media services reset restarts the session.
public final class AVCaptureEngine: CaptureEngine, @unchecked Sendable {
    private let queue = DispatchQueue(label: "MimoDays.capture")
    private static let logger = Logger(subsystem: "MimoDays", category: "Camera")
    private let session: AVCaptureSession
    private let isMultiCam: Bool
    /// P3.4: the video size setting. Touched on `queue` only, once `init` has run.
    private var videoSize: VideoSize
    /// No camera format wider than the video size allows.
    private var maxFormatWidth: Int32 { videoSize.maxFormatWidth }
    /// A size asked for during a recording: the cameras change once it ends.
    private var resizesAfterRecording = false
    private let previews: [CameraPosition: AVCaptureVideoPreviewLayer]

    // Touched on `queue` only.
    private var setup: CameraSetup?
    private var cameras: [CameraPosition: Camera] = [:]
    private var microphone: AVCaptureDeviceInput?
    private var backLens = BackLens.wide
    /// The rear camera may be the phone's virtual camera, which changes lens by itself as it zooms (P1.1). Off for the
    /// tier that tries the lens's own camera instead.
    private var usesVirtualBack = true
    /// Cameras whose focus and exposure the person locked: a new scene doesn't undo them.
    private var focusLocked: Set<CameraPosition> = []
    private var subjectObservers: [CameraPosition: any NSObjectProtocol] = [:]
    /// Where a zoom ramp is heading, so the label reads the stop, not a point on the way.
    private var rampTargets: [ObjectIdentifier: Double] = [:]
    private var recording: RecordingDelegate?
    private var pressure: [CameraPosition: CapturePressurePolicy.Level] = [:]
    /// The angles last asked for: connections made later (a lens change, a flip) start at them, not at portrait.
    private let previewAngle = Mutex<CGFloat>(90)
    private let captureAngle = Mutex<CGFloat>(90)
    /// The frame rate the current setup needed to fit the system pressure budget; pressure relief stays below it.
    private var frameRateCap = 30
    private var pressureObservations: [CameraPosition: NSKeyValueObservation] = [:]
    /// Between `start()` and `stop()`: the session should be running.
    private var isActive = false
    private var lastInterruption: CaptureInterruption?
    /// Set once in `init`.
    private var observers: [any NSObjectProtocol] = []

    private let eventSink = CaptureEventRelay()
    public var events: AsyncStream<CaptureEvent> { eventSink.stream() }

    private struct Camera {
        var input: AVCaptureDeviceInput
        var photo: AVCapturePhotoOutput
        var movie: AVCaptureMovieFileOutput
    }

    @MainActor
    public init(videoSize: VideoSize = .high) {
        let isMultiCam = AVCaptureMultiCamSession.isMultiCamSupported
        let session = isMultiCam ? AVCaptureMultiCamSession() : AVCaptureSession()
        self.isMultiCam = isMultiCam
        self.videoSize = videoSize
        self.session = session
        previews = Dictionary(uniqueKeysWithValues: CameraPosition.allCases.map { position in
            let layer = AVCaptureVideoPreviewLayer(sessionWithNoConnection: session)
            layer.videoGravity = .resizeAspectFill
            return (position, layer)
        })
        observeSystem()
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
        subjectObservers.values.forEach(NotificationCenter.default.removeObserver)
    }

    private func observeSystem() {
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: AVCaptureSession.wasInterruptedNotification, object: session, queue: nil) { [weak self] note in
                let raw = (note.userInfo?[AVCaptureSessionInterruptionReasonKey] as? NSNumber)?.intValue
                let reason = raw.flatMap(AVCaptureSession.InterruptionReason.init(rawValue:)).map(CaptureInterruption.init) ?? .other
                Self.logger.info("Session interrupted, reason \(raw ?? -1, privacy: .public)")
                guard let engine = self else { return }
                engine.queue.async {
                    engine.lastInterruption = reason
                    engine.eventSink.yield(.interrupted(reason))
                }
            },
            center.addObserver(forName: AVCaptureSession.interruptionEndedNotification, object: session, queue: nil) { [weak self] _ in
                Self.logger.info("Session interruption ended")
                guard let engine = self else { return }
                engine.queue.async { engine.eventSink.yield(.resumed) }
            },
            center.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: nil) { [weak self] note in
                let error = note.userInfo?[AVCaptureSessionErrorKey] as? AVError
                let reset = error?.code == .mediaServicesWereReset
                Self.logger.error("Session runtime error \(error?.code.rawValue ?? 0, privacy: .public)")
                guard let engine = self else { return }
                engine.queue.async { engine.runtimeError(mediaServicesWereReset: reset) }
            },
            center.addObserver(forName: Notification.Name.NSProcessInfoPowerStateDidChange, object: nil, queue: nil) { [weak self] _ in
                guard let engine = self else { return }
                engine.queue.async { engine.applyPressure() }
            },
        ]
    }

    /// When the session was last started again after an error.
    private var restartedAfterError: Date?
    private var retriesAfterError = false

    /// The session stopped on an error: it's started again at once; when it won't run, it's an interruption that
    /// the next `start()` (the app coming back) tries again.
    private func runtimeError(mediaServicesWereReset: Bool) {
        guard isActive else { return }
        // Running again: an error queued behind one the restart already got past.
        if session.isRunning, !session.isInterrupted {
            if lastInterruption != nil || mediaServicesWereReset { eventSink.yield(.resumed) }
            lastInterruption = nil
            return
        }
        // Not again within seconds: a start that fails posts another error, which mustn't start it over and over.
        // It's tried once the pause is over.
        if let restartedAfterError, case let wait = 5 - Date().timeIntervalSince(restartedAfterError), wait > 0 {
            lastInterruption = .other
            eventSink.yield(.interrupted(.other))
            guard !retriesAfterError else { return }
            retriesAfterError = true
            queue.asyncAfter(deadline: .now() + wait) { [weak self] in
                guard let self else { return }
                retriesAfterError = false
                runtimeError(mediaServicesWereReset: mediaServicesWereReset)
            }
            return
        }
        restartedAfterError = Date()
        session.startRunning()
        if session.isRunning, !session.isInterrupted {
            if lastInterruption != nil || mediaServicesWereReset { eventSink.yield(.resumed) }
            lastInterruption = nil
        } else {
            lastInterruption = .other
            eventSink.yield(.interrupted(.other))
        }
    }

    // MARK: Session

    public func start() async throws -> CameraSetup {
        let asked = CACurrentMediaTime()
        return try await onQueue {
            let began = CACurrentMediaTime()
            defer {
                Self.logger.info("Start: waited \(Self.ms(began - asked), privacy: .public) ms, took \(Self.ms(CACurrentMediaTime() - began), privacy: .public) ms, running \(self.session.isRunning, privacy: .public), interrupted \(self.session.isInterrupted, privacy: .public)")
            }
            self.isActive = true
            self.restartedAfterError = nil
            if let setup = self.setup {
                if !self.session.isRunning {
                    self.session.startRunning()
                    // Running again after an error that said "interrupted": the shutter may work again.
                    if self.session.isRunning, !self.session.isInterrupted, self.lastInterruption != nil {
                        self.lastInterruption = nil
                        self.eventSink.yield(.resumed)
                    }
                }
                return setup
            }
            let setup = try self.configureWithinBudget()
            self.setup = setup
            self.session.startRunning()
            return setup
        }
    }

    public func stop() async {
        _ = try? await onQueue {
            self.isActive = false
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    public func backLenses() async -> [BackLens] {
        (try? await onQueue {
            if let device = self.cameras[.back]?.input.device, device.isVirtualDevice { return Self.lenses(of: device) }
            let paired = self.setup == .dual
            return BackLens.allCases.filter { self.physicalBackDevice($0, paired: paired) != nil }
        }) ?? [.wide]
    }

    public func setBackLens(_ lens: BackLens) async throws {
        try await onQueue {
            // A virtual camera has the lens already: it zooms to it, no new session (P1.2). Also when it is the chosen
            // lens: a pinch may have taken the camera to another one.
            if let device = self.cameras[.back]?.input.device, device.isVirtualDevice {
                self.backLens = lens
                if let factor = Self.stop(of: lens, on: device) { self.zoom(device, to: factor, smoothly: true) }
                return
            }
            // The lens's own camera chosen again: back to its own view from wherever a pinch left it.
            guard lens != self.backLens else {
                if let device = self.cameras[.back]?.input.device { self.zoom(device, to: 1, smoothly: true) }
                return
            }
            self.backLens = lens
            guard let setup = self.setup, self.recording == nil, setup.positions.contains(.back) else { return }
            // Another lens costs the hardware differently: the setup is worked out again.
            self.removeAllCameras()
            let changed: CameraSetup
            do {
                changed = try self.configureWithinBudget()
            } catch {
                self.backLens = .wide
                do {
                    changed = try self.configureWithinBudget()
                } catch {
                    // No camera left: no setup, so captures fail instead of waiting for outputs that are gone.
                    self.setup = nil
                    throw error
                }
            }
            self.setup = changed
            self.applyPressure()
            if changed != setup { self.eventSink.yield(.setupChanged(changed)) }
        }
    }

    /// The phone's virtual rear cameras, the most lenses first.
    private static let virtualBackTypes: [AVCaptureDevice.DeviceType] = [.builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera]

    private static func lensType(_ lens: BackLens) -> AVCaptureDevice.DeviceType {
        switch lens {
        case .ultraWide: .builtInUltraWideCamera
        case .wide: .builtInWideAngleCamera
        case .telephoto: .builtInTelephotoCamera
        }
    }

    /// With two cameras, a rear device counts only in a multi-camera set with the front one (P1.1).
    private func pairs(_ device: AVCaptureDevice, paired: Bool) -> Bool {
        guard paired, isMultiCam else { return true }
        guard let front = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else { return false }
        let discovery = AVCaptureDevice.DiscoverySession(deviceTypes: [device.deviceType, .builtInWideAngleCamera], mediaType: .video, position: .unspecified)
        return discovery.supportedMultiCamDeviceSets.contains { $0.contains(device) && $0.contains(front) }
    }

    private func physicalBackDevice(_ lens: BackLens, paired: Bool) -> AVCaptureDevice? {
        AVCaptureDevice.default(Self.lensType(lens), for: .video, position: .back).flatMap { pairs($0, paired: paired) ? $0 : nil }
    }

    /// The rear camera: the virtual one when this tier allows it and it pairs, else the chosen lens's own.
    private func backDevice(_ lens: BackLens, paired: Bool) -> AVCaptureDevice? {
        if usesVirtualBack, let virtual = Self.virtualBackTypes.lazy
            .compactMap({ AVCaptureDevice.default($0, for: .video, position: .back) })
            .first(where: { self.pairs($0, paired: paired) }) {
            return virtual
        }
        return physicalBackDevice(lens, paired: paired)
    }

    /// A virtual camera's lenses in zoom order.
    private static func lenses(of device: AVCaptureDevice) -> [BackLens] {
        device.constituentDevices.compactMap { constituent in
            switch constituent.deviceType {
            case .builtInUltraWideCamera: .ultraWide
            case .builtInWideAngleCamera: .wide
            case .builtInTelephotoCamera: .telephoto
            default: nil
            }
        }
    }

    /// The device zoom factors of a camera's lenses: 1, then where a virtual camera switches to each next lens.
    private static func stops(of device: AVCaptureDevice) -> [Double] {
        guard device.isVirtualDevice else { return [1] }
        return [1] + device.virtualDeviceSwitchOverVideoZoomFactors.map { Double(truncating: $0) }
    }

    private static func stop(of lens: BackLens, on device: AVCaptureDevice) -> Double? {
        let stops = stops(of: device)
        return lenses(of: device).firstIndex(of: lens).flatMap { $0 < stops.count ? stops[$0] : nil }
    }

    public func flip() async throws -> CameraSetup {
        try await onQueue {
            guard let setup = self.setup else { throw CaptureError.notRunning }
            guard case let .single(position) = setup, self.recording == nil else { return setup }
            let flipped = CameraSetup.single(position.other)
            self.frameRateCap = 30
            self.session.beginConfiguration()
            defer { self.session.commitConfiguration() }
            self.removeCamera(position)
            // The new camera is the first one while it's added: it may take the plain microphone.
            self.setup = flipped
            do {
                try self.addCamera(position.other, formatWidth: self.maxFormatWidth, paired: false)
            } catch {
                self.setup = setup
                // Not even the old one back: no setup, so the shutter says the camera isn't there instead of waiting.
                if (try? self.addCamera(position, formatWidth: self.maxFormatWidth, paired: false)) == nil { self.setup = nil }
                throw error
            }
            return flipped
        }
    }

    public func setMicrophone(_ enabled: Bool) async throws {
        let asked = CACurrentMediaTime()
        try await onQueue {
            let began = CACurrentMediaTime()
            let changes = enabled != (self.microphone != nil)
            defer {
                if changes { Self.logger.info("Microphone \(enabled, privacy: .public): waited \(Self.ms(began - asked), privacy: .public) ms, took \(Self.ms(CACurrentMediaTime() - began), privacy: .public) ms, running \(self.session.isRunning, privacy: .public)") }
            }
            if !enabled {
                guard let microphone = self.microphone else { return }
                self.session.beginConfiguration()
                defer { self.session.commitConfiguration() }
                // Connections made by hand go by hand, before the input that feeds them.
                for connection in self.session.connections where connection.inputPorts.contains(where: { $0.input === microphone }) {
                    self.session.removeConnection(connection)
                }
                self.session.removeInput(microphone)
                self.microphone = nil
                return
            }
            guard self.microphone == nil else { return }
            guard let device = AVCaptureDevice.default(for: .audio) else { throw CaptureError.configurationFailed }
            let input = try self.deviceInput(device)
            self.session.beginConfiguration()
            defer { self.session.commitConfiguration() }
            guard self.session.canAddInput(input) else { throw CaptureError.configurationFailed }
            self.session.addInputWithNoConnections(input)
            self.microphone = input
            do {
                for (position, camera) in self.cameras { try self.connectMicrophone(to: camera.movie, position) }
            } catch {
                // Kept, it would make the next "on" a no-op while nothing records sound.
                for connection in self.session.connections where connection.inputPorts.contains(where: { $0.input === input }) {
                    self.session.removeConnection(connection)
                }
                self.session.removeInput(input)
                self.microphone = nil
                throw error
            }
        }
    }

    /// Rare lock failures leave the light as it was; the recording itself is unaffected.
    public func setTorch(_ flash: FlashMode) async {
        let mode = AVCaptureDevice.TorchMode(flash)
        try? await onQueue {
            guard let device = self.cameras[.back]?.input.device, device.hasTorch, device.isTorchModeSupported(mode) else { return }
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            device.torchMode = mode
        }
    }

    /// 90 is portrait; 0 has the top of the phone to the left, 180 to the right. Device check: C.7.
    private static func rotationAngle(_ hold: DeviceHold) -> CGFloat {
        switch hold {
        case .upright: 90
        case .landscapeLeft: 0
        case .landscapeRight: 180
        }
    }

    @MainActor
    public func setPreviewHold(_ hold: DeviceHold) {
        let angle = Self.rotationAngle(hold)
        // Under the lock, so a connection made on the session queue at the same time can't apply an older angle after this.
        previewAngle.withLock { stored in
            stored = angle
            for preview in previews.values {
                if let connection = preview.connection, connection.isVideoRotationAngleSupported(angle) {
                    connection.videoRotationAngle = angle
                }
            }
        }
    }

    public func setCaptureHold(_ hold: DeviceHold) async {
        let angle = Self.rotationAngle(hold)
        captureAngle.withLock { $0 = angle }
        try? await onQueue {
            for camera in self.cameras.values {
                for connection in [camera.photo.connection(with: .video), camera.movie.connection(with: .video)].compactMap(\.self)
                where connection.isVideoRotationAngleSupported(angle) {
                    connection.videoRotationAngle = angle
                }
            }
        }
    }

    @MainActor
    public func previewLayer(for position: CameraPosition) -> CALayer? {
        previews[position]
    }

    // MARK: Photo

    public func capturePhoto(flash: FlashMode, silent: Bool) async throws -> CapturedPhoto {
        // Two cameras at once offer no photo flash: the rear light stands in, lit a moment before the shot.
        let offered = (try? await onQueue { self.cameras[.back]?.photo.supportedFlashModes }) ?? nil
        let lights = flash != .off && offered.map { !$0.contains(AVCaptureDevice.FlashMode(flash)) } == true
        Self.logger.info("Photo flash \(flash.rawValue, privacy: .public), offered \(offered?.map(\.rawValue) ?? [], privacy: .public), light \(lights)")
        if lights {
            await setTorch(flash)
            try? await Task.sleep(for: .milliseconds(300))
        }
        do {
            let photo = try await shoot(flash: lights ? .off : flash, silent: silent)
            if lights { await setTorch(.off) }
            return photo
        } catch {
            if lights { await setTorch(.off) }
            throw error
        }
    }

    private func shoot(flash: FlashMode, silent: Bool) async throws -> CapturedPhoto {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                guard let setup = self.setup, self.session.isRunning else {
                    continuation.resume(throwing: CaptureError.notRunning)
                    return
                }
                // Only cameras that are there: the batch waits for every position it's given.
                let positions = setup.positions.filter { self.cameras[$0] != nil }
                guard !positions.isEmpty else {
                    continuation.resume(throwing: CaptureError.notRunning)
                    return
                }
                let batch = PhotoBatch(positions: positions) { continuation.resume(with: $0) }
                for position in positions {
                    guard let output = self.cameras[position]?.photo else { continue }
                    let hevc = output.availablePhotoCodecTypes.contains(.hevc)
                    let settings = hevc ? AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc]) : AVCapturePhotoSettings()
                    settings.maxPhotoDimensions = output.maxPhotoDimensions
                    let mode = AVCaptureDevice.FlashMode(flash)
                    if position == .back, output.supportedFlashModes.contains(mode) { settings.flashMode = mode }
                    if silent, output.isShutterSoundSuppressionSupported { settings.isShutterSoundSuppressionEnabled = true }
                    output.capturePhoto(with: settings, delegate: batch.delegate(for: position, fileExtension: hevc ? "heic" : "jpg"))
                }
            }
        }
    }

    // MARK: Video

    public func record(limit: Duration?) async throws -> CapturedVideo {
        try await record(limit: limit, only: nil)
    }

    public func record(limit: Duration?, only: CameraPosition?) async throws -> CapturedVideo {
        let asked = CACurrentMediaTime()
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                Self.logger.info("Record: waited \(Self.ms(CACurrentMediaTime() - asked), privacy: .public) ms for the camera, running \(self.session.isRunning, privacy: .public), interrupted \(self.session.isInterrupted, privacy: .public)")
                guard let setup = self.setup, self.session.isRunning else {
                    continuation.resume(throwing: CaptureError.notRunning)
                    return
                }
                guard self.recording == nil else {
                    continuation.resume(throwing: CaptureError.alreadyRecording)
                    return
                }
                let wanted = setup.positions.filter { only == nil || $0 == only }
                let outputs = (wanted.isEmpty ? setup.positions : wanted)
                    .compactMap { position in self.cameras[position].map { (position, $0.movie) } }
                // Each stream stops cleanly before the disk is full, keeping what it has.
                guard let budget = CaptureStorage.freeBytes().flatMap({ CaptureStorage.budgetPerStream(freeBytes: $0, streams: outputs.count) })
                else {
                    continuation.resume(throwing: CaptureError.lowStorage)
                    return
                }
                self.lastInterruption = nil
                // Sound off records none: any sound connection left on an output is switched off for this recording.
                let hasAudio = self.microphone != nil
                for (_, movie) in outputs {
                    for connection in movie.connections where connection.inputPorts.contains(where: { $0.mediaType == .audio }) {
                        connection.isEnabled = hasAudio
                    }
                }
                Self.logger.info("Recording, sound \(hasAudio), sound connections \(outputs.map { $0.1.connections.filter { $0.isEnabled && $0.inputPorts.contains { $0.mediaType == .audio } }.count }, privacy: .public)")
                let delegate = RecordingDelegate(
                    outputs: outputs.map { ($0.0, ObjectIdentifier($0.1)) }, hasAudio: hasAudio,
                    started: { self.eventSink.yield(.recordingStarted) },
                    // One stream failing ends the others too.
                    streamFailed: { Task { await self.stopRecording() } }
                ) { result in
                    self.queue.async {
                        self.recording = nil
                        self.setSmoothAutoFocus(false)
                        if self.resizesAfterRecording {
                            self.resizesAfterRecording = false
                            self.reconfigureForSize()
                        }
                        // Pressure that rose while recording can drop the selfie camera now.
                        self.applyPressure()
                        // The session tells why it was interrupted; the movie output only that it was.
                        continuation.resume(with: result.map { video in
                            var video = video
                            if video.interruption == .other, let reason = self.lastInterruption { video.interruption = reason }
                            return video
                        })
                    }
                }
                self.recording = delegate
                self.setSmoothAutoFocus(true)
                let maximum = limit.map { CMTime(seconds: TimeInterval($0.components.seconds), preferredTimescale: 600) } ?? .invalid
                for (position, movie) in outputs {
                    movie.maxRecordedDuration = maximum
                    movie.maxRecordedFileSize = budget
                    self.applyCompression(to: movie)
                    do {
                        movie.startRecording(to: try CaptureFiles.temporaryURL("mov"), recordingDelegate: delegate)
                    } catch {
                        delegate.fail(position)
                    }
                }
            }
        }
    }

    public func stopRecording() async {
        _ = try? await onQueue {
            // An output asked to start that hasn't yet isn't `isRecording`: it stops as soon as it starts.
            self.recording?.requestStop()
            for camera in self.cameras.values where camera.movie.isRecording {
                camera.movie.stopRecording()
            }
        }
    }

    public func setVideoSize(_ size: VideoSize) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async {
                defer { continuation.resume() }
                let widthChanged = size.maxFormatWidth != self.videoSize.maxFormatWidth
                self.videoSize = size
                // The bit rate applies from the next take; another width needs the cameras set up again.
                guard widthChanged, self.setup != nil else { return }
                if self.recording != nil {
                    self.resizesAfterRecording = true
                } else {
                    self.reconfigureForSize()
                }
            }
        }
    }

    public func reducedWidth() async -> Int32? {
        await withCheckedContinuation { (continuation: CheckedContinuation<Int32?, Never>) in
            queue.async {
                guard self.setup == .dual, let device = self.cameras[.back]?.input.device else { return continuation.resume(returning: nil) }
                let width = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription).width
                continuation.resume(returning: width < self.maxFormatWidth ? width : nil)
            }
        }
    }

    /// The cameras again at the video size's width, keeping what the setup can (P3.3).
    private func reconfigureForSize() {
        guard let setup else { return }
        removeAllCameras()
        if !isMultiCam { session.sessionPreset = maxFormatWidth < 1920 ? .hd1280x720 : .high }
        do {
            let changed = try configureWithinBudget()
            self.setup = changed
            applyPressure()
            if changed != setup { eventSink.yield(.setupChanged(changed)) }
        } catch {
            // No camera left: no setup, so captures fail instead of waiting for outputs that are gone.
            Self.logger.error("Video size: no camera fits, \(error.localizedDescription, privacy: .public)")
            self.setup = nil
        }
    }

    /// P3.2: HEVC where the output offers it, and the video size's bit rate where the output takes one. Only keys the
    /// output lists are set: any other is an exception, not an error. Without them the size changes the width alone.
    private func applyCompression(to movie: AVCaptureMovieFileOutput) {
        guard let connection = movie.connection(with: .video) else { return }
        let keys = movie.supportedOutputSettingsKeys(for: connection)
        let codecs = movie.availableVideoCodecTypes
        guard keys.contains(AVVideoCodecKey), let codec = codecs.contains(.hevc) ? .hevc : codecs.first else { return }
        var settings: [String: Any] = [AVVideoCodecKey: codec]
        if let bitRate = videoSize.averageBitRate, keys.contains(AVVideoCompressionPropertiesKey) {
            settings[AVVideoCompressionPropertiesKey] = [AVVideoAverageBitRateKey: bitRate]
        }
        movie.setOutputSettings(settings, for: connection)
        Self.logger.info("Video size \(self.videoSize.rawValue, privacy: .public): \(codec.rawValue, privacy: .public), bit rate \(self.videoSize.averageBitRate ?? 0, privacy: .public), keys \(keys, privacy: .public)")
    }

    // MARK: Configuration (on `queue`)

    /// Both cameras at the largest formats the hardware budget allows, then a lower frame rate if the
    /// system pressure cost is too high; the rear camera alone when nothing fits.
    private func configureWithinBudget() throws -> CameraSetup {
        frameRateCap = 30
        usesVirtualBack = true
        guard let multiCam = session as? AVCaptureMultiCamSession else {
            try configureSingleBack(formatWidth: nil)
            return .single(.back)
        }
        // The virtual rear camera with the front one; then the lens's own camera with it, at the same tiers; then one
        // camera (P1.1). A pair that can't be added at one size (busy, over budget) tries the next size down.
        let hasVirtualPair = backDevice(backLens, paired: true)?.isVirtualDevice == true
        for tier in CapturePressurePolicy.dualTiers(hasVirtualPair: hasVirtualPair, maxWidth: maxFormatWidth) {
            usesVirtualBack = tier.virtualBack
            if negotiateDual(multiCam, width: tier.width) { return .dual }
        }
        try configureSingleBack(formatWidth: maxFormatWidth)
        return .single(.back)
    }

    /// The rear camera alone: the virtual one, else the lens's own camera when the virtual one can't run here.
    private func configureSingleBack(formatWidth: Int32?) throws {
        usesVirtualBack = true
        do {
            try configure(.single(.back), formatWidth: formatWidth)
        } catch where backDevice(backLens, paired: false)?.isVirtualDevice == true {
            usesVirtualBack = false
            try configure(.single(.back), formatWidth: formatWidth)
        }
    }

    /// Both cameras at `width`, at the highest frame rate within the budget; false leaves no camera added.
    private func negotiateDual(_ multiCam: AVCaptureMultiCamSession, width: Int32) -> Bool {
        guard (try? configure(.dual, formatWidth: width)) != nil else { return false }
        for frameRate in CapturePressurePolicy.dualFrameRates {
            // The session prices a camera at its format's top rate unless the input caps it; both costs count,
            // and both cameras must take the rate.
            session.beginConfiguration()
            for camera in cameras.values { camera.input.videoMinFrameDurationOverride = CMTime(value: 1, timescale: CMTimeScale(frameRate)) }
            session.commitConfiguration()
            if setFrameRate(frameRate), multiCam.hardwareCost <= 1, multiCam.systemPressureCost <= 1 {
                frameRateCap = frameRate
                return true
            }
        }
        removeAllCameras()
        return false
    }

    private func configure(_ setup: CameraSetup, formatWidth: Int32?) throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        if !isMultiCam { session.sessionPreset = maxFormatWidth < 1920 ? .hd1280x720 : .high }
        do {
            // Both cameras record at one size: the views swap, and Halves shows them side by side (P1.0a).
            let shared = setup == .dual ? formatWidth.flatMap(sharedDimensions) : nil
            for position in setup.positions {
                try addCamera(position, formatWidth: formatWidth, paired: setup == .dual, dimensions: shared)
            }
        } catch {
            removeAllCameras()
            throw error
        }
    }

    private func removeAllCameras() {
        session.beginConfiguration()
        CameraPosition.allCases.forEach(removeCamera)
        session.commitConfiguration()
    }

    /// Whether every camera took the rate; one that can't keeps its own.
    @discardableResult
    private func setFrameRate(_ frameRate: Int) -> Bool {
        var all = true
        for camera in cameras.values {
            let device = camera.input.device
            let supported = device.activeFormat.videoSupportedFrameRateRanges.contains {
                $0.minFrameRate <= Double(frameRate) && Double(frameRate) <= $0.maxFrameRate
            }
            guard supported, (try? device.lockForConfiguration()) != nil else {
                all = false
                continue
            }
            device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: CMTimeScale(frameRate))
            device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: CMTimeScale(frameRate))
            device.unlockForConfiguration()
        }
        return all
    }

    /// Heat or load on a camera: lower the frame rate, and drop the selfie camera when it gets critical.
    private func pressureChanged(_ level: CapturePressurePolicy.Level, on position: CameraPosition) {
        pressure[position] = level
        applyPressure()
    }

    /// The worst camera pressure, with Low Power Mode, applied to the setup.
    private func applyPressure() {
        guard let setup else { return }
        let response = CapturePressurePolicy.response(
            to: pressure.values.max() ?? .nominal, lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled,
            setup: setup, isRecording: recording != nil, frameRateCap: frameRateCap
        )
        setFrameRate(response.frameRate)
        guard response.dropsSelfie else { return }
        session.beginConfiguration()
        removeCamera(.front)
        // One camera has no shared budget to stay under: back to the full rate once the heat passes.
        cameras[.back]?.input.videoMinFrameDurationOverride = .invalid
        session.commitConfiguration()
        frameRateCap = 30
        self.setup = .single(.back)
        // The rear camera was slowed for the front one's heat: its own pressure sets its rate now.
        applyPressure()
        eventSink.yield(.setupChanged(.single(.back)))
    }

    private func device(for position: CameraPosition, paired: Bool) -> AVCaptureDevice? {
        let avPosition: AVCaptureDevice.Position = position == .back ? .back : .front
        let chosen = position == .back ? backDevice(backLens, paired: paired) : nil
        return chosen ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: avPosition)
    }

    private func addCamera(_ position: CameraPosition, formatWidth: Int32?, paired: Bool, dimensions: CMVideoDimensions? = nil) throws {
        guard let device = device(for: position, paired: paired) else { throw CaptureError.cameraUnavailable }
        if isMultiCam, let formatWidth { try selectMultiCamFormat(device, maxWidth: formatWidth, dimensions: dimensions) }
        let input = try deviceInput(device)
        guard session.canAddInput(input) else { throw CaptureError.configurationFailed }
        session.addInputWithNoConnections(input)
        let photo = AVCapturePhotoOutput()
        let movie = AVCaptureMovieFileOutput()
        var added: [AVCaptureOutput] = []
        // All of it or none: a camera half added isn't in `cameras`, so nothing would ever take it out again.
        do {
            guard let port = input.ports(for: .video, sourceDeviceType: device.deviceType, sourceDevicePosition: device.position).first
            else { throw CaptureError.configurationFailed }
            for output in [photo, movie] as [AVCaptureOutput] {
                guard session.canAddOutput(output) else { throw CaptureError.configurationFailed }
                session.addOutputWithNoConnections(output)
                added.append(output)
                try connect(AVCaptureConnection(inputPorts: [port], output: output), position)
            }
            if let preview = previews[position] {
                try connect(AVCaptureConnection(inputPort: port, videoPreviewLayer: preview), position)
            }
            if microphone != nil { try connectMicrophone(to: movie, position) }
        } catch {
            for connection in session.connections where connection.inputPorts.contains(where: { $0.input === input })
                || added.contains(where: { $0 === connection.output }) {
                session.removeConnection(connection)
            }
            added.forEach(session.removeOutput)
            session.removeInput(input)
            throw error
        }
        if let largest = device.activeFormat.supportedMaxPhotoDimensions.last { photo.maxPhotoDimensions = largest }
        cameras[position] = Camera(input: input, photo: photo, movie: movie)
        prepareFocus(device, position)
        if position == .back, let factor = Self.stop(of: backLens, on: device) ?? Self.stop(of: .wide, on: device) {
            zoom(device, to: factor, smoothly: false)
        }
        pressureObservations[position] = device.observe(\.systemPressureState, options: [.initial, .new]) { [weak self] device, _ in
            guard let engine = self else { return }
            let level = CapturePressurePolicy.Level(device.systemPressureState.level)
            // A camera removed since (the selfie dropped for heat) no longer has a say.
            engine.queue.async {
                guard engine.cameras[position]?.input.device === device else { return }
                engine.pressureChanged(level, on: position)
            }
        }
    }

    /// Portrait, and mirrored for the front camera, the way people see themselves.
    private func connect(_ connection: AVCaptureConnection, _ position: CameraPosition) throws {
        guard session.canAddConnection(connection) else { throw CaptureError.configurationFailed }
        session.addConnection(connection)
        func rotate(_ angle: CGFloat) {
            if connection.isVideoRotationAngleSupported(angle) { connection.videoRotationAngle = angle }
        }
        if connection.videoPreviewLayer == nil { captureAngle.withLock { rotate($0) } } else { previewAngle.withLock { rotate($0) } }
        if position == .front, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }
    }

    /// Each camera's stream records the microphone facing its way, so whichever stream ends up the main one after a
    /// swap has the sound (Andrew, 2026-11-15). The first camera may fall back to the plain microphone; the second
    /// goes without sound rather than fail the camera.
    private func connectMicrophone(to movie: AVCaptureMovieFileOutput, _ position: CameraPosition) throws {
        guard let microphone else { return }
        let isFirst = position == setup?.positions.first ?? .back
        let avPosition: AVCaptureDevice.Position = position == .back ? .back : .front
        let port = microphone.ports(for: .audio, sourceDeviceType: microphone.device.deviceType, sourceDevicePosition: avPosition).first
            ?? (isFirst ? microphone.ports.first { $0.mediaType == .audio } : nil)
        let connection = port.map { AVCaptureConnection(inputPorts: [$0], output: movie) }
        guard let connection, session.canAddConnection(connection) else {
            if isFirst { throw CaptureError.configurationFailed }
            return
        }
        session.addConnection(connection)
    }

    private func removeCamera(_ position: CameraPosition) {
        pressureObservations[position] = nil
        pressure[position] = nil
        focusLocked.remove(position)
        subjectObservers.removeValue(forKey: position).map(NotificationCenter.default.removeObserver)
        guard let camera = cameras.removeValue(forKey: position) else { return }
        session.removeInput(camera.input)
        session.removeOutput(camera.photo)
        session.removeOutput(camera.movie)
    }

    /// The largest multi-camera format up to `maxWidth` pixels wide, so two cameras fit the hardware budget; with
    /// `dimensions`, one of exactly that size when the camera has it.
    private func selectMultiCamFormat(_ device: AVCaptureDevice, maxWidth: Int32, dimensions: CMVideoDimensions? = nil) throws {
        let formats = device.formats.filter(\.isMultiCamSupported)
        if let dimensions, let format = formats.first(where: { Self.same(Self.size($0), dimensions) }) {
            try device.lockForConfiguration()
            device.activeFormat = format
            device.unlockForConfiguration()
            return
        }
        guard let format = Self.largest(formats, upTo: maxWidth) ?? formats.min(by: { Self.size($0).width < Self.size($1).width }) else {
            throw CaptureError.configurationFailed
        }
        try device.lockForConfiguration()
        device.activeFormat = format
        device.unlockForConfiguration()
    }

    private static func size(_ format: AVCaptureDevice.Format) -> CMVideoDimensions {
        CMVideoFormatDescriptionGetDimensions(format.formatDescription)
    }

    private static func same(_ a: CMVideoDimensions, _ b: CMVideoDimensions) -> Bool { a.width == b.width && a.height == b.height }

    /// The widest format up to `maxWidth`; of equal widths the first listed, as before (P1.0a keeps today's choice).
    private static func largest(_ formats: [AVCaptureDevice.Format], upTo maxWidth: Int32) -> AVCaptureDevice.Format? {
        formats.filter { size($0).width <= maxWidth }.max { size($0).width < size($1).width }
    }

    /// The size both cameras of a pair record at: the rear camera's usual choice when the front one has it, else the
    /// biggest size both have up to `maxWidth`; nil leaves each to its own (P1.0a).
    private func sharedDimensions(_ maxWidth: Int32) -> CMVideoDimensions? {
        guard let back = device(for: .back, paired: true), let front = device(for: .front, paired: true) else { return nil }
        let backFormats = back.formats.filter(\.isMultiCamSupported)
        let frontSizes = front.formats.filter(\.isMultiCamSupported).map(Self.size)
        func frontHas(_ size: CMVideoDimensions) -> Bool { frontSizes.contains { Self.same($0, size) } }
        if let usual = Self.largest(backFormats, upTo: maxWidth).map(Self.size), frontHas(usual) { return usual }
        return backFormats.map(Self.size)
            .filter { $0.width <= maxWidth && frontHas($0) }
            .max { Int($0.width) * Int($0.height) < Int($1.width) * Int($1.height) }
    }

    // MARK: Focus and zoom (on `queue`)

    /// Continuous focus and exposure from the middle, and a new look when the scene changes (P1.5).
    private func prepareFocus(_ device: AVCaptureDevice, _ position: CameraPosition) {
        resetFocus(device)
        subjectObservers.removeValue(forKey: position).map(NotificationCenter.default.removeObserver)
        subjectObservers[position] = NotificationCenter.default.addObserver(
            forName: AVCaptureDevice.subjectAreaDidChangeNotification, object: device, queue: nil
        ) { [weak self] _ in
            guard let engine = self else { return }
            engine.queue.async {
                guard engine.cameras[position]?.input.device === device, !engine.focusLocked.contains(position) else { return }
                engine.resetFocus(device)
            }
        }
    }

    /// While recording, focus moves slowly instead of hunting in the clip (P1.5); photos keep the quick one.
    private func setSmoothAutoFocus(_ on: Bool) {
        for camera in cameras.values {
            let device = camera.input.device
            guard device.isSmoothAutoFocusSupported, (try? device.lockForConfiguration()) != nil else { continue }
            device.isSmoothAutoFocusEnabled = on
            device.unlockForConfiguration()
        }
    }

    private func resetFocus(_ device: AVCaptureDevice) {
        guard (try? device.lockForConfiguration()) != nil else { return }
        defer { device.unlockForConfiguration() }
        let middle = CGPoint(x: 0.5, y: 0.5)
        if device.isFocusPointOfInterestSupported { device.focusPointOfInterest = middle }
        if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
        if device.isExposurePointOfInterestSupported { device.exposurePointOfInterest = middle }
        if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
        device.isSubjectAreaChangeMonitoringEnabled = true
    }

    public func focus(at point: CGPoint, on position: CameraPosition, lock: Bool) async -> FocusResult {
        (try? await onQueue { () -> FocusResult in
            guard let device = self.cameras[position]?.input.device, (try? device.lockForConfiguration()) != nil else { return .none }
            defer { device.unlockForConfiguration() }
            // A lock focuses and exposes once, then holds; a tap keeps following from the new point until the scene changes.
            let focusMode: AVCaptureDevice.FocusMode = lock ? .autoFocus : .continuousAutoFocus
            let exposureMode: AVCaptureDevice.ExposureMode = lock ? .autoExpose : .continuousAutoExposure
            let focuses = device.isFocusPointOfInterestSupported && device.isFocusModeSupported(focusMode)
            let exposes = device.isExposurePointOfInterestSupported && device.isExposureModeSupported(exposureMode)
            if focuses {
                device.focusPointOfInterest = point
                device.focusMode = focusMode
            }
            if exposes {
                device.exposurePointOfInterest = point
                device.exposureMode = exposureMode
            }
            let locks = lock && (focuses || exposes)
            if locks { self.focusLocked.insert(position) } else { self.focusLocked.remove(position) }
            return FocusResult(focuses: focuses, exposes: exposes, locks: locks)
        }) ?? .none
    }

    public func zoom(on position: CameraPosition) async -> CameraZoom? {
        try? await onQueue { () -> CameraZoom? in
            guard let device = self.cameras[position]?.input.device else { return nil }
            let multiplier = Double(device.displayVideoZoomFactorMultiplier)
            let minFactor = Double(device.minAvailableVideoZoomFactor)
            let maxFactor = max(minFactor, min(Double(device.maxAvailableVideoZoomFactor), CameraZoom.maxShown / max(multiplier, 0.01)))
            // Each stop keeps its lens when the ones out of reach go.
            let lenses: [BackLens?] = device.isVirtualDevice ? Self.lenses(of: device) : []
            let stops = Self.stops(of: device).enumerated()
                .map { ($1, $0 < lenses.count ? lenses[$0] : nil) }
                .filter { $0.0 >= minFactor && $0.0 <= maxFactor }
            return CameraZoom(
                stops: stops.map(\.0),
                lenses: device.isVirtualDevice ? stops.compactMap(\.1) : [],
                minFactor: minFactor, maxFactor: maxFactor, shownMultiplier: multiplier,
                factor: device.isRampingVideoZoom ? self.rampTargets[ObjectIdentifier(device)] ?? Double(device.videoZoomFactor) : Double(device.videoZoomFactor)
            )
        }
    }

    public func setZoom(_ factor: Double, on position: CameraPosition, smoothly: Bool) async {
        _ = try? await onQueue {
            guard let device = self.cameras[position]?.input.device else { return }
            self.zoom(device, to: factor, smoothly: smoothly)
        }
    }

    private func zoom(_ device: AVCaptureDevice, to factor: Double, smoothly: Bool) {
        let minFactor = device.minAvailableVideoZoomFactor
        let maxFactor = max(minFactor, min(device.maxAvailableVideoZoomFactor, CGFloat(CameraZoom.maxShown) / max(device.displayVideoZoomFactorMultiplier, 0.01)))
        let clamped = min(max(CGFloat(factor), minFactor), maxFactor)
        guard (try? device.lockForConfiguration()) != nil else { return }
        defer { device.unlockForConfiguration() }
        rampTargets[ObjectIdentifier(device)] = Double(clamped)
        if smoothly {
            device.ramp(toVideoZoomFactor: clamped, withRate: 8)
        } else {
            device.cancelVideoZoomRamp()
            device.videoZoomFactor = clamped
        }
    }

    /// Only once allowed: an input made before would raise the system prompt itself, without our explainer.
    private func deviceInput(_ device: AVCaptureDevice) throws -> AVCaptureDeviceInput {
        let media: AVMediaType = device.hasMediaType(.audio) ? .audio : .video
        guard AVCaptureDevice.authorizationStatus(for: media) == .authorized else { throw CaptureError.cameraUnavailable }
        do {
            return try AVCaptureDeviceInput(device: device)
        } catch {
            throw CaptureError.cameraUnavailable
        }
    }

    private static func ms(_ seconds: CFTimeInterval) -> Int { Int(seconds * 1000) }

    private func onQueue<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { continuation.resume(with: Result { try work() }) }
        }
    }
}

// MARK: Delegates

/// Collects one photo per camera; succeeds only when every camera delivered.
private final class PhotoBatch: Sendable {
    private struct State {
        var results: [CameraPosition: URL?] = [:]
        var delegates: [PhotoDelegate] = []
    }

    private let positions: [CameraPosition]
    private let state = Mutex(State())
    private let completion: @Sendable (Result<CapturedPhoto, any Error>) -> Void

    init(positions: [CameraPosition], completion: @escaping @Sendable (Result<CapturedPhoto, any Error>) -> Void) {
        self.positions = positions
        self.completion = completion
    }

    /// The photo output doesn't keep its delegate alive; the batch does until it finishes.
    func delegate(for position: CameraPosition, fileExtension: String) -> PhotoDelegate {
        let delegate = PhotoDelegate(fileExtension: fileExtension) { [self] url in finish(position, url) }
        state.withLock { $0.delegates.append(delegate) }
        return delegate
    }

    private func finish(_ position: CameraPosition, _ url: URL?) {
        let outcome = state.withLock { state -> Result<CapturedPhoto, any Error>? in
            state.results.updateValue(url, forKey: position)
            guard state.results.count == positions.count else { return nil }
            state.delegates.removeAll()
            let urls = state.results.compactMapValues { $0 }
            // One camera failing doesn't lose the other's photo: it is kept as a one-camera moment.
            let taken = positions.filter { urls[$0] != nil }
            guard let main = taken.first, let mainURL = urls[main] else { return .failure(CaptureError.photoFailed) }
            let selfie = taken.dropFirst().first.flatMap { urls[$0] }
            return .success(CapturedPhoto(mainURL: mainURL, mainPosition: main, selfieURL: selfie))
        }
        if let outcome { completion(outcome) }
    }
}

private final class PhotoDelegate: NSObject, AVCapturePhotoCaptureDelegate, Sendable {
    private let fileExtension: String
    private let completion: @Sendable (URL?) -> Void

    init(fileExtension: String, completion: @escaping @Sendable (URL?) -> Void) {
        self.fileExtension = fileExtension
        self.completion = completion
    }

    func photoOutput(_: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: (any Error)?) {
        guard error == nil, let data = photo.fileDataRepresentation(), !data.isEmpty else {
            completion(nil)
            return
        }
        do {
            let url = try CaptureFiles.temporaryURL(fileExtension)
            try data.write(to: url, options: .atomic)
            completion(url)
        } catch {
            completion(nil)
        }
    }
}

/// Follows every movie output of one recording and reports once all have finished.
private final class RecordingDelegate: NSObject, AVCaptureFileOutputRecordingDelegate, Sendable {
    private struct Stream {
        var position: CameraPosition
        /// Host time of the start callback; also says the stream has begun.
        var started: TimeInterval?
        /// Its first frame on the session clock (iOS 18.2 and later).
        var firstFrame: TimeInterval?
        var result: (url: URL, duration: TimeInterval)?
        var finished = false
        var failed = false
        var interruption: CaptureInterruption?
    }

    private let streams: Mutex<[ObjectIdentifier: Stream]>
    private let stopRequested = Mutex(false)
    private let hasAudio: Bool
    /// Once, as the first stream begins writing.
    private let started: @Sendable () -> Void
    private let streamFailed: @Sendable () -> Void
    private let completion: @Sendable (Result<CapturedVideo, any Error>) -> Void

    init(
        outputs: [(CameraPosition, ObjectIdentifier)], hasAudio: Bool, started: @escaping @Sendable () -> Void,
        streamFailed: @escaping @Sendable () -> Void, completion: @escaping @Sendable (Result<CapturedVideo, any Error>) -> Void
    ) {
        streams = Mutex(Dictionary(uniqueKeysWithValues: outputs.map { ($0.1, Stream(position: $0.0)) }))
        self.hasAudio = hasAudio
        self.started = started
        self.streamFailed = streamFailed
        self.completion = completion
    }

    /// A stream that could not start at all.
    func fail(_ position: CameraPosition) {
        let outcome = streams.withLock { streams -> Result<CapturedVideo, any Error>? in
            guard let key = streams.first(where: { $0.value.position == position })?.key else { return nil }
            streams[key]?.finished = true
            streams[key]?.failed = true
            return outcomeIfDone(streams)
        }
        streamFailed()
        if let outcome { completion(outcome) }
    }

    /// Stop, also for outputs still starting.
    func requestStop() {
        stopRequested.withLock { $0 = true }
    }

    /// iOS 18.0-18.1: the callback's time stands in for the first frame's.
    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo _: URL, from _: [AVCaptureConnection]) {
        didStart(output, firstFrame: nil)
    }

    /// iOS 18.2 and later call only this one: the first frame's time on the session clock, which both cameras share,
    /// so a late callback under load doesn't shift the selfie.
    @available(iOS 18.2, *)
    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo _: URL, startPTS: CMTime, from _: [AVCaptureConnection]) {
        didStart(output, firstFrame: startPTS.isNumeric ? startPTS.seconds : nil)
    }

    private func didStart(_ output: AVCaptureFileOutput, firstFrame: TimeInterval?) {
        if stopRequested.withLock({ $0 }) { output.stopRecording() }
        let now = CACurrentMediaTime()
        let isFirst = streams.withLock { streams in
            let first = !streams.values.contains { $0.started != nil }
            streams[ObjectIdentifier(output)]?.started = now
            streams[ObjectIdentifier(output)]?.firstFrame = firstFrame
            return first
        }
        if isFirst { started() }
    }

    func fileOutput(
        _ output: AVCaptureFileOutput, didFinishRecordingTo url: URL, from _: [AVCaptureConnection], error: (any Error)?
    ) {
        // Reaching the time limit, a stop or an interruption still "finishes successfully" with a playable file.
        let succeeded = error == nil
            || ((error as NSError?)?.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool ?? false)
        let duration = output.recordedDuration.seconds
        let interruption = error.flatMap { CaptureInterruption(endingRecording: $0) }
        let outcome = streams.withLock { streams -> Result<CapturedVideo, any Error>? in
            let key = ObjectIdentifier(output)
            streams[key]?.finished = true
            if succeeded, duration > 0 {
                streams[key]?.result = (url, duration)
                streams[key]?.interruption = interruption
            } else {
                streams[key]?.failed = true
                try? FileManager.default.removeItem(at: url)
            }
            return outcomeIfDone(streams)
        }
        if !succeeded { streamFailed() }
        if let outcome { completion(outcome) }
    }

    /// Never hands back a missing or empty stream; one camera failing keeps the other's clip as a one-camera moment.
    private func outcomeIfDone(_ streams: [ObjectIdentifier: Stream]) -> Result<CapturedVideo, any Error>? {
        guard streams.values.allSatisfy(\.finished) else { return nil }
        let ordered = streams.values.filter { !$0.failed && $0.result != nil }.sorted { $0.position == .back && $1.position == .front }
        guard let main = ordered.first, let mainResult = main.result else {
            streams.values.compactMap(\.result?.url).forEach { try? FileManager.default.removeItem(at: $0) }
            return .failure(CaptureError.recordingFailed)
        }
        let selfie = ordered.count > 1 ? ordered[1] : nil
        var offset: TimeInterval = 0
        // First frames when both streams have one, else both callback times: never one clock against the other.
        if let mainStart = main.firstFrame, let selfieStart = selfie?.firstFrame {
            offset = selfieStart - mainStart
        } else if let mainStart = main.started, let selfieStart = selfie?.started {
            offset = selfieStart - mainStart
        }
        return .success(CapturedVideo(
            mainURL: mainResult.url, mainPosition: main.position, selfieURL: selfie?.result?.url,
            duration: mainResult.duration, selfieOffset: offset, hasAudio: hasAudio,
            interruption: main.interruption ?? selfie?.interruption
        ))
    }
}

extension CapturePressurePolicy.Level {
    init(_ level: AVCaptureDevice.SystemPressureState.Level) {
        switch level {
        case .nominal: self = .nominal
        case .fair: self = .fair
        case .serious: self = .serious
        case .critical: self = .critical
        case .shutdown: self = .shutdown
        default: self = .serious
        }
    }
}

extension CaptureInterruption {
    init(_ reason: AVCaptureSession.InterruptionReason) {
        switch reason {
        case .videoDeviceNotAvailableInBackground: self = .background
        case .audioDeviceInUseByAnotherClient, .videoDeviceInUseByAnotherClient, .videoDeviceNotAvailableWithMultipleForegroundApps:
            self = .anotherApp
        case .videoDeviceNotAvailableDueToSystemPressure: self = .tooWarm
        default: self = .other
        }
    }

    /// Why a movie output stopped early; nil for a stop or the time limit. A session interruption is `.other`
    /// here and gets its reason from the session.
    init?(endingRecording error: any Error) {
        switch (error as? AVError)?.code {
        case .maximumDurationReached?: return nil
        case .diskFull?, .maximumFileSizeReached?: self = .lowStorage
        default: self = .other
        }
    }
}

private extension AVCaptureDevice.FlashMode {
    init(_ mode: FlashMode) {
        switch mode {
        case .off: self = .off
        case .auto: self = .auto
        case .on: self = .on
        }
    }
}

private extension AVCaptureDevice.TorchMode {
    init(_ mode: FlashMode) {
        switch mode {
        case .off: self = .off
        case .auto: self = .auto
        case .on: self = .on
        }
    }
}
