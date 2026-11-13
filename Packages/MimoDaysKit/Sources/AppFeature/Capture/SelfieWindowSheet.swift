import DesignSystem
import SwiftUI

/// C04: corner, size and reset for the selfie window. Opens on a long press of the window or its VoiceOver action;
/// the window moves behind the sheet as the choices change.
struct SelfieWindowSheet: View {
    @Binding var placement: CameraSettings.SelfieWindow
    @State private var height: CGFloat = 276

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Selfie window", bundle: .module)
                .textStyle(.sheetTitle)
                .foregroundStyle(ColorToken.textPrimary.color)
                .accessibilityAddTraits(.isHeader)
                .padding(.bottom, 13)
            SegmentedControl(selection: $placement.corner, options: CameraSettings.SelfieWindow.Corner.allCases, fitsLabels: true) { Text($0.title) }
                .accessibilityIdentifier("selfieWindow.corner")
                .padding(.bottom, 10)
            SegmentedControl(selection: $placement.scale, options: CameraSettings.SelfieWindow.Scale.allCases) { Text($0.title) }
                .accessibilityIdentifier("selfieWindow.size")
                .padding(.bottom, 14)
            Button {
                withAnimation(.snappy) { placement = CameraSettings.SelfieWindow() }
            } label: {
                Text("Reset to default", bundle: .module)
                    .textStyle(TextStyle(.nunito, size: 15, weight: 700, relativeTo: .subheadline, maximumScale: 1.35))
                    .foregroundStyle(ColorToken.textPrimary.color)
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background {
                        Icon.shapeSegmentTrack.image.resizable().foregroundStyle(ColorToken.surfaceChip.color)
                    }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("selfieWindow.reset")
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 26)
        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { height = $0 }
        .presentationDetents([.height(height)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        .presentationBackground(ColorToken.surfaceSheet.color)
    }
}

extension CameraSettings.SelfieWindow.Corner {
    var title: LocalizedStringResource {
        switch self {
        case .topLeft: LocalizedStringResource("Top left", bundle: .atURL(Bundle.module.bundleURL))
        case .topRight: LocalizedStringResource("Top right", bundle: .atURL(Bundle.module.bundleURL))
        case .bottomLeft: LocalizedStringResource("Bottom left", bundle: .atURL(Bundle.module.bundleURL))
        case .bottomRight: LocalizedStringResource("Bottom right", bundle: .atURL(Bundle.module.bundleURL))
        }
    }
}

extension CameraSettings.SelfieWindow.Scale {
    var title: LocalizedStringResource {
        switch self {
        case .small: LocalizedStringResource("Small", bundle: .atURL(Bundle.module.bundleURL))
        case .medium: LocalizedStringResource("Medium", bundle: .atURL(Bundle.module.bundleURL))
        case .large: LocalizedStringResource("Large", bundle: .atURL(Bundle.module.bundleURL))
        }
    }
}

extension CameraSettings.SelfieWindow {
    /// VoiceOver value of the window, "Top right, Medium", joined the way the locale lists things.
    var accessibilityValue: String {
        [String(localized: corner.title), String(localized: scale.title)].formatted(.list(type: .and, width: .narrow))
    }
}
