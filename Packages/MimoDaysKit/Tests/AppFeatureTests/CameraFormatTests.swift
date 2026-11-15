@testable import AppFeature
@testable import Core
import Foundation
import Persistence
import Testing

/// C.1/C.2/C.4: the recording format, how the phone is held, and the format staying fixed while recording.
@MainActor
struct CameraFormatTests {
    private func camera(
        _ format: CaptureFormat = .portrait, hold: DeviceHold = .upright, mode: CameraSettings.Mode = .photo,
        engine: SimulatedCaptureEngine = SimulatedCaptureEngine(), store: InMemoryCameraSettingsStore? = nil,
        onCapture: @escaping @MainActor (CaptureResult) -> Void = { $0.discardFiles() }
    ) async -> (CameraModel, FixedOrientationSensor) {
        var settings = CameraSettings()
        settings.format = format
        settings.opensIn = mode
        settings.videoLength = .long
        let sensor = FixedOrientationSensor(hold)
        let model = CameraModel(
            engine: engine, store: store ?? InMemoryCameraSettingsStore(settings), isSurprise: false, orientation: sensor,
            microphoneStatus: { .denied }, onCapture: onCapture
        )
        await model.start()
        await settle { model.hold == hold }
        return (model, sensor)
    }

    private func settle(_ condition: () -> Bool) async {
        for _ in 0..<50 where !condition() { try? await Task.sleep(for: .milliseconds(20)) }
    }

    @Test func portraitIsTheDefaultAndThePickIsRemembered() async {
        #expect(CameraSettings().format == .portrait)
        let store = InMemoryCameraSettingsStore()
        let (model, _) = await camera(store: store)
        model.setFormat(.square)
        #expect(store.load().format == .square)
        // Settings saved before formats existed open in 9:16.
        let old = try? JSONDecoder().decode(CameraSettings.self, from: Data(#"{"opensIn":"video"}"#.utf8))
        #expect(old?.format == .portrait && old?.opensIn == .video)
    }

    /// Format x hold: 16:9 only on its side, 9:16 and 1:1 only upright.
    @Test func theShutterWorksOnlyWhenThePhoneIsHeldForTheFormat() async {
        for format in CaptureFormat.allCases {
            for hold in DeviceHold.allCases {
                let (model, _) = await camera(format, hold: hold)
                let fits = format == .landscape ? hold != .upright : hold == .upright
                #expect(model.formatFitsHold == fits, "\(format) \(hold)")
                #expect(model.canCapture == fits && model.needsRotation == !fits, "\(format) \(hold)")
            }
        }
    }

    @Test func turningThePhoneUnlocksTheShutter() async {
        var taken: [CaptureResult] = []
        let (model, sensor) = await camera(.landscape) { taken.append($0) }
        await model.shutter()
        #expect(taken.isEmpty)
        sensor.set(.landscapeLeft)
        await settle { model.canCapture }
        #expect(!model.needsRotation)
        await model.shutter()
        #expect(taken.map(\.format) == [.landscape])
        taken.forEach { $0.discardFiles() }
    }

    /// The file is turned the way the phone was held when the capture started.
    @Test func eachCaptureIsTurnedTheWayThePhoneIsHeld() async {
        let engine = SimulatedCaptureEngine()
        let (model, sensor) = await camera(.landscape, hold: .landscapeLeft, engine: engine)
        await model.shutter()
        sensor.set(.landscapeRight)
        await settle { model.hold == .landscapeRight }
        await model.shutter()
        model.setFormat(.square)
        sensor.set(.upright)
        await settle { model.hold == .upright }
        await model.shutter()
        #expect(await engine.captureHolds == [.landscapeLeft, .landscapeRight, .upright])
    }

    @Test func theFormatStaysFixedWhileRecording() async throws {
        let engine = SimulatedCaptureEngine()
        var taken: [CaptureResult] = []
        let (model, sensor) = await camera(.landscape, hold: .landscapeRight, mode: .video, engine: engine) { taken.append($0) }
        async let recording: Void = model.shutter()
        while await !engine.isRecording { try await Task.sleep(for: .milliseconds(20)) }
        model.setFormat(.portrait)
        #expect(model.format == .landscape)
        // Turning upright mid-recording keeps recording and keeps the layout.
        sensor.set(.upright)
        await settle { model.hold == .upright }
        #expect(model.isRecording && !model.needsRotation)
        #expect(model.layoutHold == .landscapeRight)
        await model.shutter()
        await recording
        #expect(taken.map(\.format) == [.landscape])
        #expect(model.layoutHold == .upright && model.needsRotation)
        taken.forEach { $0.discardFiles() }
    }

    @Test func gravityDecidesTheHoldWellPastTheDiagonal() {
        #expect(DeviceHold.from(gravityX: 0, y: -1, z: 0, previous: .landscapeLeft) == .upright)
        #expect(DeviceHold.from(gravityX: 0, y: 1, z: 0, previous: .landscapeLeft) == .upright)
        #expect(DeviceHold.from(gravityX: -1, y: 0, z: 0, previous: .upright) == .landscapeLeft)
        #expect(DeviceHold.from(gravityX: 1, y: 0, z: 0, previous: .upright) == .landscapeRight)
        // About 45°: no change either way.
        #expect(DeviceHold.from(gravityX: -0.7, y: -0.7, z: 0, previous: .upright) == .upright)
        #expect(DeviceHold.from(gravityX: -0.7, y: -0.7, z: 0, previous: .landscapeLeft) == .landscapeLeft)
        // Flat on a table keeps the last hold.
        #expect(DeviceHold.from(gravityX: -0.3, y: 0, z: -0.95, previous: .upright) == .upright)
    }
}
