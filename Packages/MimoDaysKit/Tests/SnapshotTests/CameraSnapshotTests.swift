@testable import AppFeature
@testable import Core
import DesignSystem
import Foundation
import Persistence
import Testing
import SnapshotTesting
import SwiftUI
import TestSupport

/// C01, C01s, C02, C03, C04, C05 with the simulated engine. The camera is dark in both appearances.
@MainActor
@Suite(.tags(.snapshot))
struct CameraSnapshotTests {
    private func camera(
        multiCam: Bool = true, surprise: Bool = false, mode: CameraSettings.Mode = .photo,
        selfieWindow: CameraSettings.SelfieWindow = .init(), microphone: PermissionStatus = .granted,
        format: CaptureFormat = .portrait, hold: DeviceHold = .upright, halves: Bool = false
    ) async -> CameraModel {
        var settings = CameraSettings()
        if halves { settings.arrangement = .halves }
        settings.opensIn = mode
        settings.selfieWindow = selfieWindow
        settings.format = format
        let model = CameraModel(
            engine: SimulatedCaptureEngine(multiCam: multiCam), store: InMemoryCameraSettingsStore(settings),
            isSurprise: surprise, orientation: FixedOrientationSensor(hold), microphoneStatus: { microphone }, onCapture: { _ in }
        )
        await model.start()
        for _ in 0..<50 where model.hold != hold { try? await Task.sleep(for: .milliseconds(20)) }
        return model
    }

    /// The camera with every permission granted, so nothing asks the system.
    private func screen(_ model: CameraModel, adjustsSelfie: Bool = false, windowHold: DeviceHold? = nil, last: Bool = false) -> some View {
        CameraView(model: model, adjustsSelfie: adjustsSelfie, windowHold: windowHold, lastCapture: last ? Self.lastCapture : nil, onClose: {})
            .environment(\.permissions, PresetPermissionService(status: .granted))
    }

    /// DG.1: a warm last capture, as on U01.
    private static let lastCapture = LastCapture(
        image: UIGraphicsImageRenderer(size: CGSize(width: 60, height: 60)).image { context in
            UIColor(red: 0.85, green: 0.55, blue: 0.40, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 60, height: 60))
        },
        open: {}
    )

    @Test func photo() async {
        assertScreenSnapshots(of: screen(await camera()))
    }

    @Test func photoOnDuo() async {
        assertScreenSnapshots(of: screen(await camera()).onDuo(), variants: SnapshotVariant.duo)
    }

    @Test func surprise() async {
        assertScreenSnapshots(of: screen(await camera(surprise: true)), variants: [SnapshotVariant(.iPhone, .light)])
    }

    /// P8.8 GG02: taking a moment again, its date in the chip.
    @Test func thenNow() async {
        let model = await camera()
        model.repeating = CaptureTime(instant: Date(timeIntervalSince1970: 1_762_872_120), timeZone: .gmt)
        assertScreenSnapshots(of: screen(model), variants: [SnapshotVariant(.iPhone, .light), SnapshotVariant(.iPhone, .light, rightToLeft: true)] + SnapshotVariant.languages)
    }

    @Test func videoIdle() async {
        assertScreenSnapshots(of: screen(await camera(mode: .video), last: true), variants: [SnapshotVariant(.iPhone, .light)])
    }

    /// 7.5 s into a 10 s clip: "00:07 / 00:10".
    @Test func recording() async {
        let model = await camera(mode: .video)
        model.phase = .recording(startedAt: Date().addingTimeInterval(-7.5))
        assertScreenSnapshots(of: screen(model), variants: [SnapshotVariant(.iPhone, .light)])
    }

    /// U02: 1:1, phone upright.
    @Test func square() async {
        assertScreenSnapshots(of: screen(await camera(mode: .video, format: .square), last: true), variants: [SnapshotVariant(.iPhone, .light), SnapshotVariant(.iPhone, .light, .accessibilityExtraLarge)])
    }

    /// U03: 16:9 picked with the phone upright: the shape, the hint and the dimmed shutter with its reason.
    @Test func landscapePickedUpright() async {
        assertScreenSnapshots(of: screen(await camera(mode: .video, format: .landscape), last: true), variants: [SnapshotVariant(.iPhone, .light), SnapshotVariant(.iPhone, .light, .accessibilityExtraLarge)])
    }

    /// U04: 16:9 with the top of the phone to the left: the layout turned, the window on its side.
    @Test func landscapeSideways() async {
        assertScreenSnapshots(of: screen(await camera(mode: .video, format: .landscape, hold: .landscapeLeft), last: true), variants: [SnapshotVariant(.iPhone, .light), SnapshotVariant(.iPhone, .light, .accessibilityExtraLarge), SnapshotVariant(.iPhone, .light, rightToLeft: true)])
    }

    /// The top to the right: the shutter's column stays on the phone's bottom edge, so the design is mirrored.
    @Test func landscapeSidewaysTheOtherWay() async {
        assertScreenSnapshots(of: screen(await camera(surprise: true, format: .landscape, hold: .landscapeRight)), variants: [SnapshotVariant(.iPhone, .light)])
    }

    /// U05: recording 16:9 sideways: the timer, the lock chip and the stop button.
    @Test func landscapeRecording() async {
        let model = await camera(mode: .video, format: .landscape, hold: .landscapeLeft)
        model.phase = .recording(startedAt: Date().addingTimeInterval(-7.5))
        assertScreenSnapshots(of: screen(model), variants: [SnapshotVariant(.iPhone, .light)])
    }

    /// U06: 9:16 picked with the phone sideways: the 9:16 shape, the hint and the reason in the column.
    @Test func portraitPickedSideways() async {
        assertScreenSnapshots(of: screen(await camera(mode: .video, hold: .landscapeLeft), last: true), variants: [SnapshotVariant(.iPhone, .light), SnapshotVariant(.iPhone, .light, .accessibilityExtraLarge)])
    }

    /// The test matrix's 1:1 cells: picked with the phone sideways (the hint, as for 9:16), and recording.
    @Test func squarePickedSideways() async {
        assertScreenSnapshots(of: screen(await camera(mode: .video, format: .square, hold: .landscapeLeft), last: true), variants: [SnapshotVariant(.iPhone, .light)])
    }

    @Test func squareRecording() async {
        let model = await camera(mode: .video, format: .square)
        model.phase = .recording(startedAt: Date().addingTimeInterval(-7.5))
        assertScreenSnapshots(of: screen(model), variants: [SnapshotVariant(.iPhone, .light)])
    }

    /// iPad: the window turns with the device, so the camera lays its sideways design out as it is (Andrew, 2026-11-15).
    @Test func iPadWindowTurned() async {
        let model = await camera(mode: .video, format: .landscape, hold: .landscapeLeft)
        assertScreenSnapshots(of: screen(model, windowHold: .landscapeLeft), variants: [SnapshotVariant(.iPadLandscape, .dark)])
        let upright = await camera(mode: .video, hold: .landscapeRight)
        assertScreenSnapshots(of: screen(upright, windowHold: .landscapeRight), variants: [SnapshotVariant(.iPadLandscape, .light)], testName: "iPadWindowTurnedWithTheWrongFormat")
    }

    @Test func singleCamera() async {
        assertScreenSnapshots(of: screen(await camera(multiCam: false)))
    }

    /// C13b: video with sound on, microphone off in Settings.
    @Test func microphoneOff() async {
        assertScreenSnapshots(of: screen(await camera(mode: .video, microphone: .denied)), variants: [SnapshotVariant(.iPhone, .light)])
    }

    /// The camera couldn't start (the simulator has no cameras).
    @Test func unavailable() async {
        let model = CameraModel(
            engine: AVCaptureEngine(), store: InMemoryCameraSettingsStore(), isSurprise: false,
            microphoneStatus: { .granted }, onCapture: { _ in }
        )
        await model.start()
        assertScreenSnapshots(of: screen(model), variants: [SnapshotVariant(.iPhone, .light)])
    }

    /// ↻ on a dual setup: the front camera big, the rear one in the window.
    @Test func swapped() async {
        let model = await camera()
        await model.flip()
        assertScreenSnapshots(of: screen(model), variants: [SnapshotVariant(.iPhone, .light)])
    }

    /// P1.4: the label after a tap, on the next lens (2×).
    @Test func zoomedIn() async {
        let model = await camera()
        model.nextZoomStop()
        assertScreenSnapshots(of: screen(model), variants: [SnapshotVariant(.iPhone, .light), SnapshotVariant(.iPhone, .light, rightToLeft: true)] + SnapshotVariant.languages)
    }

    /// P1.6: a long press on the picture: the hand-cut mark with AE/AF Lock above it.
    @Test func focusLocked() async {
        let model = await camera()
        await model.focus(at: CGPoint(x: 0.5, y: 0.4), layerPoint: CGPoint(x: 200, y: 330), on: .back, lock: true)
        assertScreenSnapshots(of: screen(model), variants: [SnapshotVariant(.iPhone, .light), SnapshotVariant(.iPhone, .light, .accessibilityExtraLarge)] + SnapshotVariant.languages)
    }

    @Test func selfieWindowHidden() async {
        let model = await camera()
        model.toggleSelfie()
        assertScreenSnapshots(of: screen(model), variants: [SnapshotVariant(.iPhone, .light)])
    }

    @Test func interruptedTooWarm() async throws {
        let engine = SimulatedCaptureEngine()
        let model = CameraModel(
            engine: engine, store: InMemoryCameraSettingsStore(), isSurprise: false,
            microphoneStatus: { .granted }, onCapture: { _ in }
        )
        await model.start()
        await engine.simulateInterruption(.tooWarm)
        for _ in 0..<50 where model.interruption == nil { try await Task.sleep(for: .milliseconds(20)) }
        assertScreenSnapshots(of: screen(model), variants: [SnapshotVariant(.iPhone, .light)])
    }

    /// C04 behind its sheet: corner targets, the chosen one in coral.
    @Test func adjustSelfieWindow() async {
        let model = await camera(selfieWindow: .init(corner: .topLeft, scale: .medium))
        assertScreenSnapshots(of: screen(model, adjustsSelfie: true), variants: [SnapshotVariant(.iPhone, .light)])
    }

    @Test func largeSelfieWindowBottomRight() async {
        let model = await camera(mode: .video, selfieWindow: .init(corner: .bottomRight, scale: .large))
        assertScreenSnapshots(of: screen(model), variants: [SnapshotVariant(.iPhone, .light)])
    }

    @Test func smallSelfieWindowBelowTheSurpriseChip() async {
        let model = await camera(surprise: true, selfieWindow: .init(corner: .topLeft, scale: .small))
        assertScreenSnapshots(of: screen(model), variants: [SnapshotVariant(.iPhone, .light)])
    }

    @Test func selfieWindowSheet() {
        assertScreenSnapshots(of: SelfieWindowSheetPreview())
    }

    /// 6.5: the composed photo, default window on a 402 × 700 preview, simulated 900 × 1200 sources.
    @Test func composedPhoto() throws {
        let window = SelfieWindowFrame(frame: CGRect(x: 266.7, y: 111.1, width: 112, height: 150), preview: CGSize(width: 402, height: 700))
        let main = try #require(SimulatedMedia.image(.back).cgImage)
        let selfie = try #require(SimulatedMedia.image(.front).cgImage)
        let composed = PhotoComposer.compose(main: main, selfie: selfie, window: window)
        assertSnapshot(of: UIImage(cgImage: composed), as: .image(precision: 0.99))
    }

    /// H.8: halves, each camera filling half of 9:16 (top and bottom) and of 16:9 held sideways (left and right).
    @Test func halves() async {
        assertScreenSnapshots(of: screen(await camera(halves: true)), variants: [SnapshotVariant(.iPhone, .light)])
    }

    @Test func halvesSideways() async {
        assertScreenSnapshots(of: screen(await camera(format: .landscape, hold: .landscapeLeft, halves: true)), variants: [SnapshotVariant(.iPhone, .light)])
    }

    /// H.8: the composed halves, simulated 900 × 1200 sources kept as 9:16.
    @Test func composedHalves() throws {
        let main = try #require(SimulatedMedia.image(.back).cgImage)
        let selfie = try #require(SimulatedMedia.image(.front).cgImage)
        assertSnapshot(of: UIImage(cgImage: PhotoComposer.compose(main: main, selfie: selfie, halves: .portrait)), as: .image(precision: 0.99))
    }

    @Test func settingsSheet() {
        assertScreenSnapshots(of: CameraSettingsSheetPreview())
    }

    /// P3.3: the iPhone holds both cameras at 720p while High is chosen.
    @Test func settingsSheetReducedSize() {
        assertScreenSnapshots(of: CameraSettingsSheetPreview(reducedWidth: 1280), variants: [SnapshotVariant(.iPhone, .light)])
    }
}

/// The sheet's content on its own (a presented sheet doesn't render in snapshots).
private struct CameraSettingsSheetPreview: View {
    var reducedWidth: Int32?
    @State private var settings = CameraSettings()
    var body: some View { CameraSettingsSheet(settings: $settings, lenses: [.ultraWide, .wide, .telephoto], reducedWidth: reducedWidth) }
}

private struct SelfieWindowSheetPreview: View {
    @State private var placement = CameraSettings.SelfieWindow(corner: .topLeft)
    var body: some View {
        SelfieWindowSheet(placement: $placement)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(ColorToken.surfaceSheet.color)
    }
}
