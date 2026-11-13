@testable import AppFeature
@testable import Core
import DesignSystem
import Foundation
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
        selfieWindow: CameraSettings.SelfieWindow = .init()
    ) async -> CameraModel {
        var settings = CameraSettings()
        settings.opensIn = mode
        settings.selfieWindow = selfieWindow
        let model = CameraModel(
            engine: SimulatedCaptureEngine(multiCam: multiCam), store: InMemoryCameraSettingsStore(settings),
            isSurprise: surprise, microphoneAllowed: { true }, onCapture: { _ in }
        )
        await model.start()
        return model
    }

    /// The camera with every permission granted, so nothing asks the system.
    private func screen(_ model: CameraModel, adjustsSelfie: Bool = false) -> some View {
        CameraView(model: model, adjustsSelfie: adjustsSelfie, onClose: {})
            .environment(\.permissions, PresetPermissionService(status: .granted))
    }

    @Test func photo() async {
        assertScreenSnapshots(of: screen(await camera()))
    }

    @Test func surprise() async {
        assertScreenSnapshots(of: screen(await camera(surprise: true)), variants: [SnapshotVariant(.iPhone, .light)])
    }

    @Test func videoIdle() async {
        assertScreenSnapshots(of: screen(await camera(mode: .video)), variants: [SnapshotVariant(.iPhone, .light)])
    }

    /// 7.5 s into a 10 s clip: "00:07 / 00:10".
    @Test func recording() async {
        let model = await camera(mode: .video)
        model.phase = .recording(startedAt: Date().addingTimeInterval(-7.5))
        assertScreenSnapshots(of: screen(model), variants: [SnapshotVariant(.iPhone, .light)])
    }

    @Test func singleCamera() async {
        assertScreenSnapshots(of: screen(await camera(multiCam: false)))
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

    @Test func settingsSheet() {
        assertScreenSnapshots(of: CameraSettingsSheetPreview())
    }
}

/// The sheet's content on its own (a presented sheet doesn't render in snapshots).
private struct CameraSettingsSheetPreview: View {
    @State private var settings = CameraSettings()
    var body: some View { CameraSettingsSheet(settings: $settings) }
}

private struct SelfieWindowSheetPreview: View {
    @State private var placement = CameraSettings.SelfieWindow(corner: .topLeft)
    var body: some View {
        SelfieWindowSheet(placement: $placement)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(ColorToken.surfaceSheet.color)
    }
}
