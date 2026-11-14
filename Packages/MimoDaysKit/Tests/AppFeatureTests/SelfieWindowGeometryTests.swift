@testable import AppFeature
import CoreGraphics
import Persistence
import Testing

/// 9.17/9.21: one window geometry for review, the player and export - the camera's layout on the media at
/// full width, saved as a share of the frame.
struct SelfieWindowGeometryTests {
    private let layout = SelfieWindowLayout.media(width: 402, aspectRatio: 9.0 / 16.0, topInset: 62)

    @Test func theMediaLayoutIsTheCamerasOnTheFullWidthFrame() {
        #expect(layout.preview.width == 402)
        #expect(abs(layout.preview.height - 402 * 16 / 9) < 0.001)
        let saved = PiPLayout(layout.windowFrame(CameraSettings.SelfieWindow()), source: .frontSource)
        #expect(abs(saved.scale - 112.0 / 402.0) < 0.0001)
    }

    @Test func everyCornerAndSizeComesBackFromItsSavedLayout() {
        for corner in CameraSettings.SelfieWindow.Corner.allCases {
            for scale in CameraSettings.SelfieWindow.Scale.allCases {
                let placement = CameraSettings.SelfieWindow(corner: corner, scale: scale)
                let saved = PiPLayout(layout.windowFrame(placement), source: .frontSource)
                #expect(layout.placement(nearest: saved) == placement)
            }
        }
    }

    /// Layouts saved before 9.17 on Andrew's phone (window off the frame, or far too big).
    @Test func oddSavedLayoutsLandInTheNearestCornerAndSize() {
        let offFrame = PiPLayout(centerX: -0.605, centerY: 1.982, scale: 2.409)
        #expect(layout.placement(nearest: offFrame) == .init(corner: .bottomLeft, scale: .large))
        let tooBig = PiPLayout(centerX: 0.697, centerY: 0.774, scale: 0.454)
        #expect(layout.placement(nearest: tooBig) == .init(corner: .bottomRight, scale: .large))
    }
}
