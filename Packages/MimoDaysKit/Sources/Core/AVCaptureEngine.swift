import AVFoundation
import QuartzCore
import Synchronization

/// The device cameras. `AVCaptureMultiCamSession` with rear + front when supported, otherwise one
/// `AVCaptureSession` camera at a time. Each camera has its own photo and movie output (separate streams).
/// All session work runs on one serial queue.
public final class AVCaptureEngine: CaptureEngine, @unchecked Sendable {
    private let queue = DispatchQueue(label: "MimoDays.capture")
    private let session: AVCaptureSession
    private let isMultiCam: Bool
    private let previews: [CameraPosition: AVCaptureVideoPreviewLayer]

    // Touched on `queue` only.
    private var setup: CameraSetup?
    private var cameras: [CameraPosition: Camera] = [:]
    private var microphone: AVCaptureDeviceInput?
    private var recording: RecordingDelegate?
    private var pressure: [CameraPosition: CapturePressurePolicy.Level] = [:]
    private var pressureObservations: [CameraPosition: NSKeyValueObservation] = [:]

    public let events: AsyncStream<CaptureEvent>
    private let eventSink: AsyncStream<CaptureEvent>.Continuation

    private struct Camera {
        var input: AVCaptureDeviceInput
        var photo: AVCapturePhotoOutput
        var movie: AVCaptureMovieFileOutput
    }

    @MainActor
    public init() {
        let isMultiCam = AVCaptureMultiCamSession.isMultiCamSupported
        let session = isMultiCam ? AVCaptureMultiCamSession() : AVCaptureSession()
        self.isMultiCam = isMultiCam
        self.session = session
        (events, eventSink) = AsyncStream.makeStream()
        previews = Dictionary(uniqueKeysWithValues: CameraPosition.allCases.map { position in
            let layer = AVCaptureVideoPreviewLayer(sessionWithNoConnection: session)
            layer.videoGravity = .resizeAspectFill
            return (position, layer)
        })
    }

    // MARK: Session

    public func start() async throws -> CameraSetup {
        try await onQueue {
            if let setup = self.setup {
                if !self.session.isRunning { self.session.startRunning() }
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
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    public func flip() async throws -> CameraSetup {
        try await onQueue {
            guard let setup = self.setup else { throw CaptureError.notRunning }
            guard case let .single(position) = setup, self.recording == nil else { return setup }
            let flipped = CameraSetup.single(position.other)
            self.session.beginConfiguration()
            defer { self.session.commitConfiguration() }
            self.removeCamera(position)
            do {
                try self.addCamera(position.other)
            } catch {
                try? self.addCamera(position)
                throw error
            }
            self.setup = flipped
            return flipped
        }
    }

    public func setMicrophone(_ enabled: Bool) async throws {
        try await onQueue {
            if !enabled {
                if let microphone = self.microphone { self.session.removeInput(microphone) }
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
            if let main = self.setup?.positions.first, let movie = self.cameras[main]?.movie {
                try self.connectMicrophone(to: movie)
            }
        }
    }

    @MainActor
    public func previewLayer(for position: CameraPosition) -> CALayer? {
        previews[position]
    }

    // MARK: Photo

    public func capturePhoto(flash: Bool) async throws -> CapturedPhoto {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                guard let setup = self.setup, self.session.isRunning else {
                    continuation.resume(throwing: CaptureError.notRunning)
                    return
                }
                let batch = PhotoBatch(positions: setup.positions) { continuation.resume(with: $0) }
                for position in setup.positions {
                    guard let output = self.cameras[position]?.photo else { continue }
                    let hevc = output.availablePhotoCodecTypes.contains(.hevc)
                    let settings = hevc ? AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc]) : AVCapturePhotoSettings()
                    settings.maxPhotoDimensions = output.maxPhotoDimensions
                    if flash, position == .back, output.supportedFlashModes.contains(.on) { settings.flashMode = .on }
                    output.capturePhoto(with: settings, delegate: batch.delegate(for: position, fileExtension: hevc ? "heic" : "jpg"))
                }
            }
        }
    }

    // MARK: Video

    public func record(limit: Duration?) async throws -> CapturedVideo {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                guard let setup = self.setup, self.session.isRunning else {
                    continuation.resume(throwing: CaptureError.notRunning)
                    return
                }
                guard self.recording == nil else {
                    continuation.resume(throwing: CaptureError.alreadyRecording)
                    return
                }
                let outputs = setup.positions.compactMap { position in self.cameras[position].map { (position, $0.movie) } }
                let delegate = RecordingDelegate(
                    outputs: outputs.map { ($0.0, ObjectIdentifier($0.1)) }, hasAudio: self.microphone != nil,
                    // One stream failing ends the others too.
                    streamFailed: { Task { await self.stopRecording() } }
                ) { result in
                    self.queue.async {
                        self.recording = nil
                        // Pressure that rose while recording can drop the selfie camera now.
                        if let position = self.pressure.max(by: { $0.value < $1.value })?.key, let level = self.pressure[position] {
                            self.pressureChanged(level, on: position)
                        }
                    }
                    continuation.resume(with: result)
                }
                self.recording = delegate
                let maximum = limit.map { CMTime(seconds: TimeInterval($0.components.seconds), preferredTimescale: 600) } ?? .invalid
                for (position, movie) in outputs {
                    movie.maxRecordedDuration = maximum
                    do {
                        movie.startRecording(to: try Self.temporaryURL("mov"), recordingDelegate: delegate)
                    } catch {
                        delegate.fail(position)
                    }
                }
            }
        }
    }

    public func stopRecording() async {
        _ = try? await onQueue {
            for camera in self.cameras.values where camera.movie.isRecording {
                camera.movie.stopRecording()
            }
        }
    }

    // MARK: Configuration (on `queue`)

    /// Both cameras at the largest formats the hardware budget allows, then a lower frame rate if the
    /// system pressure cost is too high; the rear camera alone when nothing fits.
    private func configureWithinBudget() throws -> CameraSetup {
        guard let multiCam = session as? AVCaptureMultiCamSession else {
            try configure(.single(.back), formatWidth: nil)
            return .single(.back)
        }
        for width in CapturePressurePolicy.dualFormatWidths {
            try configure(.dual, formatWidth: width)
            if multiCam.hardwareCost <= 1 {
                for frameRate in [30, 24, 15] where multiCam.systemPressureCost > 1 {
                    setFrameRate(frameRate)
                }
                if multiCam.systemPressureCost <= 1 { return .dual }
            }
            removeAllCameras()
        }
        try configure(.single(.back), formatWidth: CapturePressurePolicy.dualFormatWidths[0])
        return .single(.back)
    }

    private func configure(_ setup: CameraSetup, formatWidth: Int32?) throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        if !isMultiCam { session.sessionPreset = .high }
        do {
            for position in setup.positions { try addCamera(position, formatWidth: formatWidth) }
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

    private func setFrameRate(_ frameRate: Int) {
        for camera in cameras.values {
            let device = camera.input.device
            let supported = device.activeFormat.videoSupportedFrameRateRanges.contains {
                $0.minFrameRate <= Double(frameRate) && Double(frameRate) <= $0.maxFrameRate
            }
            guard supported, (try? device.lockForConfiguration()) != nil else { continue }
            device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: CMTimeScale(frameRate))
            device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: CMTimeScale(frameRate))
            device.unlockForConfiguration()
        }
    }

    /// Heat or load on a camera: lower the frame rate, and drop the selfie camera when it gets critical.
    private func pressureChanged(_ level: CapturePressurePolicy.Level, on position: CameraPosition) {
        pressure[position] = level
        guard let setup, let worst = pressure.values.max() else { return }
        let response = CapturePressurePolicy.response(to: worst, setup: setup, isRecording: recording != nil)
        setFrameRate(response.frameRate)
        guard response.dropsSelfie else { return }
        session.beginConfiguration()
        removeCamera(.front)
        session.commitConfiguration()
        self.setup = .single(.back)
        eventSink.yield(.setupChanged(.single(.back)))
    }

    private func addCamera(_ position: CameraPosition, formatWidth: Int32? = CapturePressurePolicy.dualFormatWidths[0]) throws {
        let avPosition: AVCaptureDevice.Position = position == .back ? .back : .front
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: avPosition) else {
            throw CaptureError.cameraUnavailable
        }
        if isMultiCam, let formatWidth { try selectMultiCamFormat(device, maxWidth: formatWidth) }
        let input = try deviceInput(device)
        guard session.canAddInput(input) else { throw CaptureError.configurationFailed }
        session.addInputWithNoConnections(input)
        guard let port = input.ports(for: .video, sourceDeviceType: device.deviceType, sourceDevicePosition: device.position).first
        else { throw CaptureError.configurationFailed }

        let photo = AVCapturePhotoOutput()
        let movie = AVCaptureMovieFileOutput()
        for output in [photo, movie] as [AVCaptureOutput] {
            guard session.canAddOutput(output) else { throw CaptureError.configurationFailed }
            session.addOutputWithNoConnections(output)
            try connect(AVCaptureConnection(inputPorts: [port], output: output), position)
        }
        if let preview = previews[position] {
            try connect(AVCaptureConnection(inputPort: port, videoPreviewLayer: preview), position)
        }
        if let largest = device.activeFormat.supportedMaxPhotoDimensions.last { photo.maxPhotoDimensions = largest }
        cameras[position] = Camera(input: input, photo: photo, movie: movie)
        pressureObservations[position] = device.observe(\.systemPressureState, options: [.initial, .new]) { [weak self] device, _ in
            guard let engine = self else { return }
            let level = CapturePressurePolicy.Level(device.systemPressureState.level)
            engine.queue.async { engine.pressureChanged(level, on: position) }
        }
        if microphone != nil, position == setup?.positions.first ?? .back { try connectMicrophone(to: movie) }
    }

    /// Portrait, and mirrored for the front camera, the way people see themselves.
    private func connect(_ connection: AVCaptureConnection, _ position: CameraPosition) throws {
        guard session.canAddConnection(connection) else { throw CaptureError.configurationFailed }
        session.addConnection(connection)
        if connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
        if position == .front, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }
    }

    private func connectMicrophone(to movie: AVCaptureMovieFileOutput) throws {
        guard let microphone else { return }
        let port = microphone.ports(for: .audio, sourceDeviceType: microphone.device.deviceType, sourceDevicePosition: .back).first
            ?? microphone.ports.first { $0.mediaType == .audio }
        guard let port else { throw CaptureError.configurationFailed }
        let connection = AVCaptureConnection(inputPorts: [port], output: movie)
        guard session.canAddConnection(connection) else { throw CaptureError.configurationFailed }
        session.addConnection(connection)
    }

    private func removeCamera(_ position: CameraPosition) {
        pressureObservations[position] = nil
        pressure[position] = nil
        guard let camera = cameras.removeValue(forKey: position) else { return }
        session.removeInput(camera.input)
        session.removeOutput(camera.photo)
        session.removeOutput(camera.movie)
    }

    /// The largest multi-camera format up to `maxWidth` pixels wide, so two cameras fit the hardware budget.
    private func selectMultiCamFormat(_ device: AVCaptureDevice, maxWidth: Int32) throws {
        let formats = device.formats.filter(\.isMultiCamSupported)
        func width(_ format: AVCaptureDevice.Format) -> Int32 { CMVideoFormatDescriptionGetDimensions(format.formatDescription).width }
        guard let format = formats.filter({ width($0) <= maxWidth }).max(by: { width($0) < width($1) })
            ?? formats.min(by: { width($0) < width($1) }) else {
            throw CaptureError.configurationFailed
        }
        try device.lockForConfiguration()
        device.activeFormat = format
        device.unlockForConfiguration()
    }

    private func deviceInput(_ device: AVCaptureDevice) throws -> AVCaptureDeviceInput {
        do {
            return try AVCaptureDeviceInput(device: device)
        } catch {
            throw CaptureError.cameraUnavailable
        }
    }

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
            guard urls.count == positions.count, let main = positions.first, let mainURL = urls[main] else {
                urls.values.forEach { try? FileManager.default.removeItem(at: $0) }
                return .failure(CaptureError.photoFailed)
            }
            let selfie = positions.dropFirst().first.flatMap { urls[$0] }
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
            let url = try AVCaptureEngine.temporaryURL(fileExtension)
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
        var started: TimeInterval?
        var result: (url: URL, duration: TimeInterval)?
        var finished = false
        var failed = false
    }

    private let streams: Mutex<[ObjectIdentifier: Stream]>
    private let hasAudio: Bool
    private let streamFailed: @Sendable () -> Void
    private let completion: @Sendable (Result<CapturedVideo, any Error>) -> Void

    init(
        outputs: [(CameraPosition, ObjectIdentifier)], hasAudio: Bool, streamFailed: @escaping @Sendable () -> Void,
        completion: @escaping @Sendable (Result<CapturedVideo, any Error>) -> Void
    ) {
        streams = Mutex(Dictionary(uniqueKeysWithValues: outputs.map { ($0.1, Stream(position: $0.0)) }))
        self.hasAudio = hasAudio
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

    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo _: URL, from _: [AVCaptureConnection]) {
        let now = CACurrentMediaTime()
        streams.withLock { $0[ObjectIdentifier(output)]?.started = now }
    }

    func fileOutput(
        _ output: AVCaptureFileOutput, didFinishRecordingTo url: URL, from _: [AVCaptureConnection], error: (any Error)?
    ) {
        // Reaching the time limit or a stop still "finishes successfully".
        let succeeded = error == nil
            || ((error as NSError?)?.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool ?? false)
        let duration = output.recordedDuration.seconds
        let outcome = streams.withLock { streams -> Result<CapturedVideo, any Error>? in
            let key = ObjectIdentifier(output)
            streams[key]?.finished = true
            if succeeded, duration > 0 {
                streams[key]?.result = (url, duration)
            } else {
                streams[key]?.failed = true
                try? FileManager.default.removeItem(at: url)
            }
            return outcomeIfDone(streams)
        }
        if !succeeded { streamFailed() }
        if let outcome { completion(outcome) }
    }

    /// Never hands back a clip with a missing or empty stream.
    private func outcomeIfDone(_ streams: [ObjectIdentifier: Stream]) -> Result<CapturedVideo, any Error>? {
        guard streams.values.allSatisfy(\.finished) else { return nil }
        let ordered = streams.values.sorted { $0.position == .back && $1.position == .front }
        guard !ordered.contains(where: \.failed), let main = ordered.first, let mainResult = main.result else {
            ordered.compactMap(\.result?.url).forEach { try? FileManager.default.removeItem(at: $0) }
            return .failure(CaptureError.recordingFailed)
        }
        let selfie = ordered.count > 1 ? ordered[1] : nil
        var offset: TimeInterval = 0
        if let mainStart = main.started, let selfieStart = selfie?.started { offset = selfieStart - mainStart }
        return .success(CapturedVideo(
            mainURL: mainResult.url, mainPosition: main.position, selfieURL: selfie?.result?.url,
            duration: mainResult.duration, selfieOffset: offset, hasAudio: hasAudio
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
