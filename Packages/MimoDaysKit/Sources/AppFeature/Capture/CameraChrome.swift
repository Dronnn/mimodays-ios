import Core
import SwiftUI

/// U04-U07: the screen stays upright and the camera draws its sideways layout itself, like the Camera app
/// (Andrew, 2026-11-15). Each control has a box in the frame the person sees; `CameraTurn` puts the box on the
/// upright screen and turns it to stay upright, so turning the phone slides the controls and spins them in place.
struct CameraTurn {
    let hold: DeviceHold
    /// The area on the upright screen.
    let screen: CGSize
    /// False when the window has turned with the device itself (iPad, Andrew 2026-11-15): the layout for `hold`
    /// is drawn as it is.
    var turnsItself = true

    /// The area as the person sees it.
    var size: CGSize { hold.isLandscape && turnsItself ? CGSize(width: screen.height, height: screen.width) : screen }

    var angle: Angle {
        guard turnsItself else { return .zero }
        return switch hold {
        case .upright: .zero
        case .landscapeLeft: .degrees(90)
        case .landscapeRight: .degrees(-90)
        }
    }

    /// A point the person sees, on the screen. The top of the phone to the left turns the person's right
    /// into the screen's bottom; to the right, into the screen's top.
    func point(_ point: CGPoint) -> CGPoint {
        guard turnsItself else { return point }
        return switch hold {
        case .upright: point
        case .landscapeLeft: CGPoint(x: screen.width - point.y, y: point.x)
        case .landscapeRight: CGPoint(x: point.y, y: screen.height - point.x)
        }
    }

    /// A rectangle the person sees, on the screen.
    func rect(_ rect: CGRect) -> CGRect {
        let center = point(CGPoint(x: rect.midX, y: rect.midY))
        let size = hold.isLandscape && turnsItself ? CGSize(width: rect.height, height: rect.width) : rect.size
        return CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
    }
}

/// Where each control goes, in the frame the person sees. Upright: the C01-C05 layout. Sideways (U04-U06): the
/// buttons are a column on the phone's top edge and the shutter's column stays on its bottom edge, so with the
/// top to the right the design is mirrored. Upright follows the language's direction; sideways is physical.
struct CameraChrome {
    let turn: CameraTurn
    let topInset: CGFloat
    let isRightToLeft: Bool

    enum Button: CaseIterable { case close, flash, middle, more }

    private var size: CGSize { turn.size }
    private var sideways: Bool { turn.hold.isLandscape }
    /// The buttons' column is on the person's right (the top of the phone to the right).
    private var columnOnRight: Bool { turn.hold == .landscapeRight }
    private var mirrors: Bool { sideways ? columnOnRight : isRightToLeft }

    /// Mirrors a box laid out for the design's side (buttons on the left, U04).
    private func sided(_ rect: CGRect) -> CGRect {
        mirrors ? CGRect(x: size.width - rect.maxX, y: rect.minY, width: rect.width, height: rect.height) : rect
    }

    /// The design's leading side as an alignment in the content's own direction.
    func leading(_ vertical: VerticalAlignment = .center) -> Alignment {
        // Upright, `leading` already follows the language; sideways the side is physical.
        Alignment(horizontal: sideways ? physical(right: columnOnRight) : .leading, vertical: vertical)
    }

    /// A physical side as an alignment in the content's own direction.
    func physical(right: Bool) -> HorizontalAlignment {
        right != isRightToLeft ? .trailing : .leading
    }

    // MARK: Over the preview

    func button(_ button: Button) -> CGRect {
        let side: CGFloat = 40
        if sideways {
            let y: CGFloat = switch button {
            case .close: 24
            case .flash: 96
            case .middle: size.height - 136
            case .more: size.height - 64
            }
            return sided(CGRect(x: 20, y: y, width: side, height: side))
        }
        let x: CGFloat = switch button {
        case .close: 16
        case .flash: size.width / 2 - 83
        case .middle: size.width / 2 + 43
        case .more: size.width - 16 - side
        }
        return sided(CGRect(x: x, y: topInset - 8, width: side, height: side))
    }

    /// Clear of the buttons: sideways the window keeps this far from the column's side (U04).
    static let sidewaysColumnSpace: CGFloat = 76

    /// C03 timer, centred at the top.
    var timer: CGRect {
        CGRect(x: 0, y: sideways ? 22 : topInset - 6, width: size.width, height: 36)
    }

    /// C01s chip: under the buttons upright, beside them sideways. Laid out from its top; it grows downwards.
    var surpriseChip: CGRect {
        sideways
            ? sided(CGRect(x: Self.sidewaysColumnSpace, y: 27, width: 320, height: 120))
            : CGRect(x: 16, y: topInset + 48, width: size.width - 32, height: 120)
    }

    /// The corner the chip sits in, which a window there must stay below.
    var surpriseCorner: CameraSettings.SelfieWindow.Corner {
        mirrors ? .topRight : .topLeft
    }

    /// The 9:16 / 16:9 / 1:1 picker; next to the 10/30/60 s picker sideways, above it upright.
    func formatPicker(withDuration: Bool) -> CGRect {
        if sideways, withDuration {
            return CGRect(x: 0, y: size.height - 46, width: durationSplit - 6, height: 30)
        }
        return CGRect(x: 0, y: size.height - 46 - (withDuration ? 44 : 0), width: size.width, height: 30)
    }

    var durationPicker: CGRect {
        sideways
            ? CGRect(x: durationSplit + 6, y: size.height - 45, width: size.width - durationSplit - 6, height: 28)
            : CGRect(x: 0, y: size.height - 44, width: size.width, height: 28)
    }

    /// Where the two pickers meet sideways: their 210 + 12 + 168 pt row is centred (U04).
    private var durationSplit: CGFloat { size.width / 2 + 21 }

    /// U05 lock chip, where the format picker was.
    var lockChip: CGRect {
        CGRect(x: 0, y: size.height - 46, width: size.width, height: 30)
    }

    /// C05/C13 note cards, standing on the format picker.
    func note(above picker: CGRect, gap: CGFloat) -> CGRect {
        let top = sideways ? 24 : topInset + 40
        let width = sideways ? min(size.width - 2 * Self.sidewaysColumnSpace, 420) : size.width - 32
        return CGRect(x: (size.width - width) / 2, y: top, width: width, height: max(0, picker.minY - gap - top))
    }

    /// The selfie window's layout over `area` (in the person's frame).
    func selfieWindow(in area: CGRect, insideShape: Bool, chipBottom: CGFloat?) -> SelfieWindowLayout {
        let chip = chipBottom.map { (corner: surpriseCorner, bottom: $0) }
        if sideways { return .sideways(preview: area.size, columnOnRight: columnOnRight, chip: chip) }
        guard insideShape else { return SelfieWindowLayout(preview: area.size, topInset: topInset, chip: chip) }
        // 17 pt inside the frame (U02), and clear of the buttons and the pickers where the frame reaches them
        // (a 9:16 frame on the iPad's squarer screen): where the window starts and stops on the whole preview.
        let full = SelfieWindowLayout(preview: size, topInset: topInset)
        return SelfieWindowLayout(
            preview: area.size, topInset: max(0, topInset + full.topMargin - 17 - area.minY),
            bottomMargin: max(17, full.bottomMargin - (size.height - area.maxY)), topMargin: 17
        )
    }

    // MARK: The bar under the preview

    /// The shutter's column, sideways, is the 140 pt bar turned: its centre line keeps the shutter where it is upright.
    struct Bar {
        let turn: CameraTurn
        let isRightToLeft: Bool

        static let height: CGFloat = 140
        private static let shutterLine: CGFloat = 90

        private var size: CGSize { turn.size }
        private var sideways: Bool { turn.hold.isLandscape }

        /// The column's centre, across it: the same screen line for both sideways holds.
        private var line: CGFloat { turn.hold == .landscapeRight ? Self.height - Self.shutterLine : Self.shutterLine }

        private func box(_ center: CGPoint, _ size: CGSize) -> CGRect {
            CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
        }

        /// Sideways, `offset` is along the column from the shutter, positive downwards.
        private func sidewaysBox(_ offset: CGFloat, _ size: CGSize) -> CGRect {
            box(CGPoint(x: line, y: self.size.height / 2 + offset), size)
        }

        func shutter(_ side: CGFloat) -> CGRect {
            sideways
                ? sidewaysBox(0, CGSize(width: side, height: side))
                : box(CGPoint(x: size.width / 2, y: Self.shutterLine), CGSize(width: side, height: side))
        }

        /// PHOTO / VIDEO: above the shutter; sideways one over the other (U04).
        var modeSwitch: CGRect {
            sideways
                ? sidewaysBox(-72, CGSize(width: Self.height, height: 48))
                : CGRect(x: 0, y: 14, width: size.width, height: 44)
        }

        var flip: CGRect {
            let side: CGFloat = 48
            if sideways { return box(CGPoint(x: line, y: size.height - 50), CGSize(width: side, height: side)) }
            let x = isRightToLeft ? 60 : size.width - 60
            return box(CGPoint(x: x, y: Self.shutterLine), CGSize(width: side, height: side))
        }

        /// U01: the last capture, across the shutter from the flip button; sideways at the top of the column (U04, U06).
        var lastCapture: CGRect {
            let side: CGFloat = 52
            if sideways { return box(CGPoint(x: line, y: 50), CGSize(width: side, height: side)) }
            let x = isRightToLeft ? size.width - 60 : 60
            return box(CGPoint(x: x, y: Self.shutterLine), CGSize(width: side, height: side))
        }

        /// C03 "Tap to stop", upright only: sideways the column has no room (U05).
        var tapToStop: CGRect {
            CGRect(x: 0, y: 16, width: size.width, height: 28)
        }

        /// U03/U07: the line under the dimmed shutter; sideways a few short lines in the column.
        var rotateReason: CGRect {
            sideways
                ? sidewaysBox(42 + 10 + 35, CGSize(width: Self.height - 16, height: 70))
                : CGRect(x: 16, y: Self.height - 30, width: size.width - 32, height: 40)
        }
    }
}

extension View {
    /// Lays the view out in `box` (in the person's frame), then puts it on the upright screen turned to stay
    /// upright. Layout inside the box follows `direction`; the screen itself is laid out left to right.
    func turned(_ box: CGRect, _ turn: CameraTurn, alignment: Alignment = .center, direction: LayoutDirection) -> some View {
        frame(width: box.width, height: box.height, alignment: alignment)
            .environment(\.layoutDirection, direction)
            .rotationEffect(turn.angle)
            .position(turn.point(CGPoint(x: box.midX, y: box.midY)))
    }
}
