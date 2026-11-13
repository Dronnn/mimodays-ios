@testable import AppFeature
import Core
import Foundation
import Testing
import SwiftUI
import TestSupport

/// C01, C01s, C02, C03, C05 with the simulated engine. The camera is dark in both appearances.
@MainActor
@Suite(.tags(.snapshot))
struct CameraSnapshotTests {
    private func camera(
        multiCam: Bool = true, surprise: Bool = false, mode: CameraSettings.Mode = .photo
    ) async -> CameraModel {
        var settings = CameraSettings()
        settings.opensIn = mode
        let model = CameraModel(
            engine: SimulatedCaptureEngine(multiCam: multiCam), store: InMemoryCameraSettingsStore(settings),
            isSurprise: surprise, microphoneAllowed: { true }, onCapture: { _ in }
        )
        await model.start()
        return model
    }

    @Test func photo() async {
        assertScreenSnapshots(of: CameraView(model: await camera(), onClose: {}))
    }

    @Test func surprise() async {
        assertScreenSnapshots(of: CameraView(model: await camera(surprise: true), onClose: {}), variants: [SnapshotVariant(.iPhone, .light)])
    }

    @Test func videoIdle() async {
        assertScreenSnapshots(of: CameraView(model: await camera(mode: .video), onClose: {}), variants: [SnapshotVariant(.iPhone, .light)])
    }

    /// 7.5 s into a 10 s clip: "00:07 / 00:10".
    @Test func recording() async {
        let model = await camera(mode: .video)
        model.phase = .recording(startedAt: Date().addingTimeInterval(-7.5))
        assertScreenSnapshots(of: CameraView(model: model, onClose: {}), variants: [SnapshotVariant(.iPhone, .light)])
    }

    @Test func singleCamera() async {
        assertScreenSnapshots(of: CameraView(model: await camera(multiCam: false), onClose: {}))
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
