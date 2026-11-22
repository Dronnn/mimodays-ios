import Core
import DesignSystem
import Persistence
import SwiftUI

/// U01 `Camera / Format picker`: 9:16, 16:9 and 1:1 pills over the bottom of the preview.
struct FormatPicker: View {
    let selection: CaptureFormat
    let select: (CaptureFormat) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(CaptureFormat.allCases, id: \.self) { format in
                let isSelected = format == selection
                Button { select(format) } label: {
                    HStack(spacing: 3) {
                        FormatGlyph(format: format)
                            .stroke(lineWidth: 1.8)
                            .frame(width: 16, height: 16)
                            .accessibilityHidden(true)
                        Text(verbatim: format.label)
                            .textStyle(.cameraChip)
                    }
                    .foregroundStyle(isSelected ? CameraPalette.chipText : CameraPalette.cream)
                    .frame(minWidth: 66, minHeight: 30)
                    .background(
                        isSelected ? AnyShapeStyle(CameraPalette.cream) : AnyShapeStyle(CameraPalette.background.opacity(0.5)),
                        in: Capsule()
                    )
                    .frame(minHeight: Size.minimumTapTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(format.accessibilityName)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityIdentifier("camera.format.\(format.rawValue)")
            }
        }
        .padding(.vertical, -7)
        .environment(\.layoutDirection, .leftToRight)
    }
}

/// U05 `Camera / Format locked`: the format while a recording runs.
struct FormatLockedChip: View {
    let format: CaptureFormat

    var body: some View {
        HStack(spacing: 6) {
            Icon.glyphLock.image
                .resizable()
                .frame(width: 16, height: 16)
                .accessibilityHidden(true)
            Text(verbatim: format.label)
                .textStyle(.cameraChip)
        }
        .foregroundStyle(CameraPalette.cream)
        .padding(.leading, 12)
        .padding(.trailing, 16)
        .frame(minHeight: 30)
        .background(CameraPalette.background.opacity(0.55), in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Format locked while recording: \(format.accessibilityName)", bundle: .module, comment: "Camera (U05): spoken for the lock chip while a video records, e.g. 'Format locked while recording: 16 by 9'"))
        .accessibilityIdentifier("camera.formatLocked")
    }
}

/// The small frame drawn in each pill: tall, wide or square.
private struct FormatGlyph: Shape {
    let format: CaptureFormat

    func path(in rect: CGRect) -> Path {
        let size: CGSize = switch format {
        case .portrait: CGSize(width: 7, height: 13)
        case .landscape: CGSize(width: 13, height: 7)
        case .square: CGSize(width: 10, height: 10)
        }
        let scale = rect.width / 16
        let box = CGRect(
            x: rect.midX - size.width * scale / 2, y: rect.midY - size.height * scale / 2,
            width: size.width * scale, height: size.height * scale
        )
        return Path(roundedRect: box, cornerRadius: 1.5 * scale)
    }
}

/// U02/U03/U06: the chosen shape on the preview. Outside it the preview is dimmed; a thin cream line marks it.
/// Only a guide: both cameras keep their full frames.
struct FormatMask: View {
    let frame: CGRect

    var body: some View {
        ZStack {
            Rectangle()
                .fill(CameraPalette.background.opacity(0.85))
                .reverseMask { Rectangle().frame(width: frame.width, height: frame.height).position(x: frame.midX, y: frame.midY) }
            Rectangle()
                .stroke(CameraPalette.cream, lineWidth: 1)
                .frame(width: frame.width, height: frame.height)
                .position(x: frame.midX, y: frame.midY)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The chosen shape on a preview of `size`: as large as fits, centred.
    static func frame(_ format: CaptureFormat, in size: CGSize) -> CGRect {
        MomentComposition.fitted(aspect: format.aspectRatio, in: CGRect(origin: .zero, size: size), fit: .showAll)
    }
}

/// U03/U06 `Camera / To landscape` and `To portrait`: the phone is held the wrong way for the format.
struct RotateHint: View {
    let format: CaptureFormat

    var body: some View {
        VStack(spacing: 0) {
            RotateGlyph(toLandscape: format == .landscape)
                .frame(width: 64, height: 64)
                .accessibilityHidden(true)
            title
                .textStyle(TextStyle(.body, size: 17, weight: 800, relativeTo: .headline, maximumScale: 1.35))
                .foregroundStyle(CameraPalette.cream)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
            body(format)
                .textStyle(TextStyle(.body, size: 13, weight: 600, relativeTo: .footnote, maximumScale: 1.35))
                .foregroundStyle(CameraPalette.cream.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.top, 5)
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 22)
        .frame(width: 300)
        .background(CameraPalette.background.opacity(0.78), in: HandCutCard())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("camera.rotateHint")
    }

    private var title: Text {
        format == .landscape
            ? Text("Turn your phone sideways", bundle: .module, comment: "Camera (U03): 16:9 is picked and the phone is upright")
            : Text("Turn your phone upright", bundle: .module, comment: "Camera (U06): 9:16 or 1:1 is picked and the phone is sideways")
    }

    private func body(_ format: CaptureFormat) -> Text {
        switch format {
        case .landscape: Text("16:9 records in landscape", bundle: .module, comment: "Camera (U03): under 'Turn your phone sideways'")
        case .portrait, .square: Text("9:16 and 1:1 record upright", bundle: .module, comment: "Camera (U06): under 'Turn your phone upright'")
        }
    }
}

/// `Glyph / Rotate to landscape` (and its mirror for upright): the phone now (dashed), where it goes, and a coral turn arrow.
private struct RotateGlyph: View {
    let toLandscape: Bool

    var body: some View {
        Canvas { context, size in
            let scale = size.width / 64
            func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> Path {
                Path(roundedRect: CGRect(x: x * scale, y: y * scale, width: w * scale, height: h * scale), cornerRadius: 5 * scale)
            }
            let from = toLandscape ? rect(8, 5, 22, 38) : rect(18, 35, 40, 22)
            let to = toLandscape ? rect(18, 35, 40, 22) : rect(8, 5, 22, 38)
            // Where the phone is now, dashed; where it goes, solid.
            context.stroke(from, with: .color(CameraPalette.cream.opacity(0.6)), style: StrokeStyle(lineWidth: 2.5 * scale, lineCap: .round, dash: [2 * scale, 4 * scale]))
            context.stroke(to, with: .color(CameraPalette.cream), lineWidth: 3 * scale)
            var arrow = Path()
            arrow.move(to: CGPoint(x: 38 * scale, y: 7 * scale))
            arrow.addQuadCurve(to: CGPoint(x: 55 * scale, y: 26 * scale), control: CGPoint(x: 53 * scale, y: 9 * scale))
            arrow.move(to: CGPoint(x: 50 * scale, y: 22 * scale))
            arrow.addLine(to: CGPoint(x: 55 * scale, y: 27 * scale))
            arrow.addLine(to: CGPoint(x: 60 * scale, y: 22 * scale))
            context.stroke(arrow, with: .color(CameraPalette.coral), style: StrokeStyle(lineWidth: 3 * scale, lineCap: .round, lineJoin: .round))
        }
    }
}

/// U03/U07: the line under the dimmed shutter that says why.
struct RotateReason: View {
    let format: CaptureFormat
    let mode: CameraSettings.Mode
    /// One line under the shutter upright; a few short ones in the sideways column.
    var lines = 1

    var body: some View {
        text
            .textStyle(TextStyle(.body, size: 12, weight: 600, relativeTo: .caption1, maximumScale: 1.35))
            .foregroundStyle(CameraPalette.cream.opacity(0.7))
            .multilineTextAlignment(.center)
            // Fixed lines at every size; the shutter's VoiceOver hint says the same.
            .lineLimit(lines)
            .minimumScaleFactor(0.7)
            .accessibilityIdentifier("camera.rotateReason")
    }

    private var text: Text {
        switch (mode, format == .landscape) {
        case (.video, true): Text("Recording starts working once the phone is sideways", bundle: .module, comment: "Camera (U03): under the dimmed record button")
        case (.video, false): Text("Recording starts working once the phone is upright", bundle: .module, comment: "Camera (U06): under the dimmed record button")
        case (.photo, true): Text("The shutter works once the phone is sideways", bundle: .module, comment: "Camera: under the dimmed photo shutter when 16:9 is picked")
        case (.photo, false): Text("The shutter works once the phone is upright", bundle: .module, comment: "Camera: under the dimmed photo shutter when 9:16 or 1:1 is picked")
        }
    }
}

extension CaptureFormat {
    /// "9:16", "16:9", "1:1": the same in every language.
    var label: String {
        switch self {
        case .portrait: "9:16"
        case .landscape: "16:9"
        case .square: "1:1"
        }
    }

    var accessibilityName: Text {
        switch self {
        case .portrait: Text("Vertical, 9 by 16", bundle: .module, comment: "Camera format pill, spoken: the tall 9:16 format")
        case .landscape: Text("Horizontal, 16 by 9", bundle: .module, comment: "Camera format pill, spoken: the wide 16:9 format")
        case .square: Text("Square, 1 by 1", bundle: .module, comment: "Camera format pill, spoken: the square 1:1 format")
        }
    }
}

private extension View {
    /// Shows this view everywhere except where `mask` draws.
    func reverseMask<Mask: View>(@ViewBuilder _ mask: () -> Mask) -> some View {
        self.mask {
            Rectangle()
                .overlay { mask().blendMode(.destinationOut) }
                .compositingGroup()
        }
    }
}
