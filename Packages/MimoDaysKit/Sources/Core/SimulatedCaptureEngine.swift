import AVFoundation
import QuartzCore
import UIKit

/// A camera that renders its own media: the simulator (no cameras) and UI tests. Behaves like the
/// device engine (setups, flip, limits, separate streams) so the capture UI runs unchanged.
public actor SimulatedCaptureEngine: CaptureEngine {
    nonisolated let multiCam: Bool
    /// Free disk space as the engine sees it; nil means plenty.
    nonisolated let freeBytes: Int64?
    private var setup: CameraSetup?
    private var isRunning = false
    private var interruption: CaptureInterruption?
    /// Why the current recording is being stopped, when it isn't the person or the limit.
    private var stopReason: CaptureInterruption?
    private(set) var hasMicrophone = false
    private(set) var isRecording = false
    private var stopSignal: CheckedContinuation<Void, Never>?
    public nonisolated let events: AsyncStream<CaptureEvent>
    private let eventSink: AsyncStream<CaptureEvent>.Continuation

    public init(multiCam: Bool = true, freeBytes: Int64? = nil) {
        self.multiCam = multiCam
        self.freeBytes = freeBytes
        (events, eventSink) = AsyncStream.makeStream()
    }

    /// A call, the app going to the background, heat: a recording ends with what it has.
    public func simulateInterruption(_ reason: CaptureInterruption) {
        interruption = reason
        if isRecording {
            stopReason = reason
            signalStop()
        }
        eventSink.yield(.interrupted(reason))
    }

    public func simulateInterruptionEnded() {
        interruption = nil
        eventSink.yield(.resumed)
    }

    /// Heat or load the way the device engine would see it (tests and UI tests).
    public func simulatePressure(_ level: CapturePressurePolicy.Level) {
        guard let setup else { return }
        if CapturePressurePolicy.response(to: level, setup: setup, isRecording: isRecording).dropsSelfie {
            self.setup = .single(.back)
            eventSink.yield(.setupChanged(.single(.back)))
        }
    }

    public func start() -> CameraSetup {
        let setup = setup ?? (multiCam ? .dual : .single(.back))
        self.setup = setup
        isRunning = true
        return setup
    }

    public func stop() {
        isRunning = false
        signalStop()
    }

    public func flip() throws -> CameraSetup {
        guard let setup else { throw CaptureError.notRunning }
        guard case let .single(position) = setup, !isRecording else { return setup }
        self.setup = .single(position.other)
        return .single(position.other)
    }

    public func setMicrophone(_ enabled: Bool) {
        hasMicrophone = enabled
    }

    public func capturePhoto(flash _: Bool, silent _: Bool) throws -> CapturedPhoto {
        guard isRunning, interruption == nil, let setup else { throw CaptureError.notRunning }
        let urls = try setup.positions.map { position in
            let url = try CaptureFiles.temporaryURL("jpg")
            guard let data = SimulatedMedia.image(position).jpegData(compressionQuality: 0.8) else { throw CaptureError.photoFailed }
            try data.write(to: url, options: .atomic)
            return url
        }
        return CapturedPhoto(mainURL: urls[0], mainPosition: setup.positions[0], selfieURL: urls.dropFirst().first)
    }

    public func record(limit: Duration?) async throws -> CapturedVideo {
        guard isRunning, interruption == nil, let setup else { throw CaptureError.notRunning }
        guard !isRecording else { throw CaptureError.alreadyRecording }
        if let freeBytes, CaptureStorage.budgetPerStream(freeBytes: freeBytes, streams: setup.positions.count) == nil {
            throw CaptureError.lowStorage
        }
        isRecording = true
        stopReason = nil
        defer { isRecording = false }

        let clock = ContinuousClock()
        let started = clock.now
        await withCheckedContinuation { continuation in
            stopSignal = continuation
            if let limit {
                Task { [weak self] in
                    try? await Task.sleep(for: limit)
                    await self?.signalStop()
                }
            }
        }
        var elapsed = started.duration(to: clock.now)
        if let limit { elapsed = min(elapsed, limit) }
        let seconds = max(0.5, Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18)

        var urls: [URL] = []
        do {
            for position in setup.positions {
                urls.append(try await SimulatedMedia.writeClip(position, seconds: seconds))
            }
        } catch {
            urls.forEach { try? FileManager.default.removeItem(at: $0) }
            throw CaptureError.recordingFailed
        }
        return CapturedVideo(
            mainURL: urls[0], mainPosition: setup.positions[0], selfieURL: urls.dropFirst().first,
            duration: seconds, selfieOffset: 0, hasAudio: false, interruption: stopReason
        )
    }

    public func stopRecording() {
        signalStop()
    }

    private func signalStop() {
        stopSignal?.resume()
        stopSignal = nil
    }

    @MainActor
    public func previewLayer(for position: CameraPosition) -> CALayer? {
        let layer = CALayer()
        layer.contents = SimulatedMedia.image(position).cgImage
        layer.contentsGravity = .resizeAspectFill
        layer.masksToBounds = true
        return layer
    }
}

/// Plain generated frames: a warm gradient for the rear camera, a mint one for the front.
enum SimulatedMedia {
    static func size(_ position: CameraPosition) -> CGSize {
        position == .back ? CGSize(width: 900, height: 1200) : CGSize(width: 360, height: 480)
    }

    private static func colors(_ position: CameraPosition) -> [CGColor] {
        position == .back
            ? [UIColor(red: 0.98, green: 0.80, blue: 0.62, alpha: 1).cgColor, UIColor(red: 0.85, green: 0.42, blue: 0.36, alpha: 1).cgColor]
            : [UIColor(red: 0.78, green: 0.93, blue: 0.86, alpha: 1).cgColor, UIColor(red: 0.36, green: 0.62, blue: 0.58, alpha: 1).cgColor]
    }

    static func image(_ position: CameraPosition) -> UIImage {
        let size = size(position)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            draw(position, in: context.cgContext, size: size, phase: 0)
        }
    }

    /// A gradient with a disc that moves with `phase` (0...1), so video frames differ.
    private static func draw(_ position: CameraPosition, in context: CGContext, size: CGSize, phase: CGFloat) {
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors(position) as CFArray, locations: [0, 1]) {
            context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
        }
        let radius = size.width * 0.18
        let center = CGPoint(x: size.width * (0.25 + 0.5 * phase), y: size.height * 0.45)
        context.setFillColor(UIColor(white: 1, alpha: 0.55).cgColor)
        context.fillEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    }

    /// An H.264 clip at 10 fps, half the photo size.
    static func writeClip(_ position: CameraPosition, seconds: Double) async throws -> URL {
        let url = try CaptureFiles.temporaryURL("mov")
        let size = CGSize(width: size(position).width / 2, height: size(position).height / 2)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: size.width, AVVideoHeightKey: size.height,
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: size.width, kCVPixelBufferHeightKey as String: size.height,
        ])
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? CaptureError.recordingFailed }
        writer.startSession(atSourceTime: .zero)

        let fps: Int32 = 10
        let frames = max(1, Int((seconds * Double(fps)).rounded()))
        for frame in 0...frames {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
            guard let pool = adaptor.pixelBufferPool else { throw CaptureError.recordingFailed }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
            guard let buffer else { throw CaptureError.recordingFailed }
            CVPixelBufferLockBaseAddress(buffer, [])
            if let context = CGContext(
                data: CVPixelBufferGetBaseAddress(buffer), width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
            ) {
                draw(position, in: context, size: size, phase: CGFloat(frame) / CGFloat(frames))
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            // The last frame sits exactly at the clip's end so the duration comes out right.
            let time = frame == frames ? CMTime(seconds: seconds, preferredTimescale: 600) : CMTime(value: CMTimeValue(frame), timescale: fps)
            guard adaptor.append(buffer, withPresentationTime: time) else { throw writer.error ?? CaptureError.recordingFailed }
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? CaptureError.recordingFailed }
        return url
    }
}
