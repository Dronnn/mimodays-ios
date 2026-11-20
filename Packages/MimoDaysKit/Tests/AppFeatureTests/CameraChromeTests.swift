@testable import AppFeature
import Core
import CoreGraphics
import Testing

/// C.3: the camera draws its sideways layout on the upright screen (U04-U07).
@MainActor
struct CameraChromeTests {
    private let preview = CGSize(width: 402, height: 700)
    private let bar = CGSize(width: 402, height: CameraChrome.Bar.height)

    private func chrome(_ hold: DeviceHold, rightToLeft: Bool = false) -> CameraChrome {
        CameraChrome(turn: CameraTurn(hold: hold, screen: preview), topInset: 62, isRightToLeft: rightToLeft)
    }

    private func onScreen(_ rect: CGRect, _ hold: DeviceHold, _ size: CGSize? = nil) -> CGRect {
        CameraTurn(hold: hold, screen: size ?? preview).rect(rect)
    }

    @Test func sidewaysTheFrameTurnsAndFillsTheSameScreen() {
        for hold in DeviceHold.allCases {
            let turn = CameraTurn(hold: hold, screen: preview)
            let whole = CGRect(origin: .zero, size: turn.size)
            #expect(turn.rect(whole) == CGRect(origin: .zero, size: preview), "\(hold)")
        }
        #expect(CameraTurn(hold: .landscapeLeft, screen: preview).size == CGSize(width: 700, height: 402))
        // The person's top left is the screen's top right with the phone's top to the left, its bottom left the other way.
        #expect(CameraTurn(hold: .landscapeLeft, screen: preview).point(.zero) == CGPoint(x: 402, y: 0))
        #expect(CameraTurn(hold: .landscapeRight, screen: preview).point(.zero) == CGPoint(x: 0, y: 700))
    }

    @Test func uprightIsTheCameraAsBefore() {
        let upright = chrome(.upright)
        #expect(upright.button(.close) == CGRect(x: 16, y: 54, width: 40, height: 40))
        #expect(upright.button(.more).maxX == 386)
        #expect(chrome(.upright, rightToLeft: true).button(.close).maxX == 386)
        #expect(upright.formatPicker(withDuration: true).maxY == upright.durationPicker.minY - 16)
        #expect(upright.durationPicker.maxY == 684)
    }

    /// The buttons are a column on the phone's top edge and the shutter stays on its bottom edge, both ways round.
    @Test func sidewaysTheButtonsHugTheTopEdgeAndTheShutterStays() {
        for hold in [DeviceHold.landscapeLeft, .landscapeRight] {
            for button in CameraChrome.Button.allCases {
                let box = onScreen(chrome(hold).button(button), hold)
                #expect(box.minY == 20, "\(hold) \(button)")
            }
            let close = onScreen(chrome(hold).button(.close), hold)
            // Close is at the person's top: the screen's right edge with the top to the left, its left edge otherwise.
            #expect(hold == .landscapeLeft ? close.maxX == 402 - 24 : close.minX == 24, "\(hold)")
            let turn = CameraTurn(hold: hold, screen: bar)
            let shutter = turn.rect(CameraChrome.Bar(turn: turn, isRightToLeft: false).shutter(84))
            let upright = CameraChrome.Bar(turn: CameraTurn(hold: .upright, screen: bar), isRightToLeft: false).shutter(84)
            #expect(shutter == upright, "\(hold)")
        }
    }

    @Test func sidewaysThePickersSitSideBySideAtThePersonsBottom() {
        let sideways = chrome(.landscapeLeft)
        let format = sideways.formatPicker(withDuration: true)
        let duration = sideways.durationPicker
        #expect(format.maxY == 402 - 16 && abs(format.midY - duration.midY) < 0.001)
        #expect(duration.minX - format.maxX == 12)
        #expect(sideways.formatPicker(withDuration: false).width == 700)
    }

    /// The window lies on its side and keeps clear of the buttons' column, whichever side it is on.
    @Test func sidewaysTheSelfieWindowLiesDownClearOfTheButtons() {
        for hold in [DeviceHold.landscapeLeft, .landscapeRight] {
            let chrome = chrome(hold)
            let area = CGRect(origin: .zero, size: CGSize(width: 700, height: 402))
            let layout = chrome.selfieWindow(in: area, insideShape: false, chipBottom: nil)
            #expect(layout.frameSize(.medium) == CGSize(width: 150, height: 112))
            let column = chrome.button(.close)
            for corner in CameraSettings.SelfieWindow.Corner.allCases {
                let center = layout.center(corner, .large)
                let size = layout.windowSize(.large)
                let window = CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
                #expect(window.minX > column.maxX + 8 || window.maxX < column.minX - 8, "\(hold) \(corner)")
                #expect(window.maxY <= chrome.formatPicker(withDuration: true).minY, "\(hold) \(corner)")
            }
        }
    }

    /// iPhone Duo's outer display has no status bar above the screen: the controls still keep clear of the edge.
    @Test func withoutATopInsetTheControlsKeepClearOfTheEdge() {
        #expect(CameraChrome.topInset(0) == CameraChrome.bareTopInset)
        #expect(CameraChrome.topInset(62) == 62)
        let chrome = CameraChrome(turn: CameraTurn(hold: .upright, screen: CGSize(width: 382, height: 678)), topInset: CameraChrome.topInset(0), isRightToLeft: false)
        for button in CameraChrome.Button.allCases {
            #expect(chrome.button(button).minY >= 8, "\(button)")
        }
    }
}
