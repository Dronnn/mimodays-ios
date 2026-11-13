@testable import AppFeature
import Core
import CoreGraphics
import Foundation
import Testing

struct SelfieWindowLayoutTests {
    typealias Corner = CameraSettings.SelfieWindow.Corner
    /// iPhone 17 Pro-sized preview: 874 high minus the 140 pt bar and the 34 pt home indicator.
    private let layout = SelfieWindowLayout(preview: CGSize(width: 402, height: 700), topInset: 62)

    @Test func defaultMatchesTheDesign() {
        #expect(CameraSettings.SelfieWindow() == .init(corner: .topRight, scale: .medium))
        // C01: frame 112 × 150 at x 266.7, y 111.1, plus 10 pt for the handle.
        let center = layout.center(.topRight, .medium)
        #expect(abs(center.x - (266.7 + 56)) < 0.01)
        #expect(abs(center.y - (111.1 + 80)) < 0.01)
    }

    @Test func cornersFollowC04() {
        // Targets at x 9.2 / 267.2 and y 111.1 / 415.1 (the window sits 0.5 pt left of its target).
        let frames = Corner.allCases.map { corner in
            let center = layout.frameCenter(corner, .medium)
            return CGPoint(x: center.x - 56, y: center.y - 75)
        }
        let expected = [CGPoint(x: 8.7, y: 111.1), CGPoint(x: 266.7, y: 111.1), CGPoint(x: 8.7, y: 415), CGPoint(x: 266.7, y: 415)]
        for (frame, design) in zip(frames, expected) {
            #expect(abs(frame.x - design.x) < 0.01 && abs(frame.y - design.y) < 0.2)
        }
    }

    @Test(arguments: Corner.allCases)
    func sizesKeepTheCornersEdges(corner: Corner) {
        for scale in CameraSettings.SelfieWindow.Scale.allCases {
            let size = SelfieWindowLayout.windowSize(scale)
            let center = layout.center(corner, scale)
            let edgeX = corner.isLeft ? center.x - size.width / 2 : layout.preview.width - (center.x + size.width / 2)
            let edgeY = corner.isTop ? center.y - size.height / 2 : layout.preview.height - (center.y + size.height / 2)
            #expect(abs(edgeX - (corner.isLeft ? 8.7 : 23.3)) < 0.01)
            #expect(abs(edgeY - (corner.isTop ? 111.1 : 125)) < 0.01)
        }
    }

    @Test func sizesAreAQuarterAroundMedium() {
        #expect(SelfieWindowLayout.frameSize(.small) == CGSize(width: 84, height: 112.5))
        #expect(SelfieWindowLayout.frameSize(.large) == CGSize(width: 140, height: 187.5))
    }

    /// Large windows on the same side never overlap, so every corner stays reachable.
    @Test func largeWindowsStayApart() {
        let top = layout.center(.topLeft, .large).y + SelfieWindowLayout.windowSize(.large).height / 2
        let bottom = layout.center(.bottomLeft, .large).y - SelfieWindowLayout.windowSize(.large).height / 2
        #expect(top < bottom)
    }

    @Test func aWindowInTheChipsCornerStartsBelowIt() {
        let chip = SelfieWindowLayout(preview: layout.preview, topInset: 62, chip: (.topLeft, 144))
        let size = SelfieWindowLayout.windowSize(.medium)
        #expect(abs(chip.center(.topLeft, .medium).y - size.height / 2 - 156) < 0.01)
        #expect(chip.center(.topRight, .medium) == layout.center(.topRight, .medium))
        // Right to left the chip is on the right.
        let rtl = SelfieWindowLayout(preview: layout.preview, topInset: 62, chip: (.topRight, 144))
        #expect(abs(rtl.center(.topRight, .medium).y - size.height / 2 - 156) < 0.01)
        #expect(rtl.center(.topLeft, .medium) == layout.center(.topLeft, .medium))
    }

    @Test func dropsSnapToTheNearestCorner() {
        let topRight = layout.center(.topRight, .medium)
        #expect(layout.nearest(to: CGPoint(x: topRight.x - 100, y: topRight.y + 40), .medium) == .topRight)
        #expect(layout.nearest(to: CGPoint(x: 60, y: 200), .medium) == .topLeft)
        #expect(layout.nearest(to: CGPoint(x: 80, y: 650), .medium) == .bottomLeft)
        #expect(layout.nearest(to: CGPoint(x: 380, y: 520), .medium) == .bottomRight)
    }
}

@MainActor
struct SelfieWindowSettingsTests {
    @Test func placementIsSavedAndRestored() throws {
        let defaults = try #require(UserDefaults(suiteName: "SelfieWindowSettingsTests"))
        defaults.removePersistentDomain(forName: "SelfieWindowSettingsTests")
        let store = UserDefaultsCameraSettingsStore(defaults: defaults)
        var settings = store.load()
        settings.selfieWindow = .init(corner: .bottomLeft, scale: .large)
        store.save(settings)
        #expect(UserDefaultsCameraSettingsStore(defaults: defaults).load().selfieWindow == .init(corner: .bottomLeft, scale: .large))
    }

    @Test func theCameraKeepsWhatTheUserChose() async {
        let store = InMemoryCameraSettingsStore()
        let model = CameraModel(
            engine: SimulatedCaptureEngine(), store: store, isSurprise: false, microphoneAllowed: { true }, onCapture: { _ in }
        )
        model.settings.selfieWindow.corner = .bottomRight
        #expect(store.settings.selfieWindow.corner == .bottomRight)
    }
}

struct SelfieWindowAccessibilityTests {
    @Test func voiceOverReadsCornerAndSize() {
        #expect(CameraSettings.SelfieWindow().accessibilityValue == "Top right, Medium")
    }
}
