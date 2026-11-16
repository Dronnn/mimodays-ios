import Core
import DesignSystem
import Persistence
import SwiftUI

/// The camera's ••• sheet: the S03 camera settings without leaving the camera (Andrew, 2026-11-13).
struct CameraSettingsSheet: View {
    @Binding var settings: CameraSettings
    /// The rear lenses this phone can use; the choice shows with more than one.
    var lenses: [BackLens] = []
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    section(Text("Format", bundle: .module, comment: "Camera ••• sheet: section title over the 9:16 / 16:9 / 1:1 choice")) {
                        SegmentedControl(selection: $settings.format, options: CaptureFormat.allCases) { Text(verbatim: $0.label) }
                            .accessibilityIdentifier("cameraSettings.format")
                    }
                    section(Text("Flash", bundle: .module)) {
                        SegmentedControl(selection: $settings.flash, options: FlashMode.allCases) { $0.label }
                            .accessibilityIdentifier("cameraSettings.flash")
                    }
                    if lenses.count > 1 {
                        section(Text("Back camera", bundle: .module, comment: "Camera ••• sheet: section title over the rear lens choice")) {
                            SegmentedControl(selection: $settings.backLens, options: lenses, fitsLabels: true) { $0.label }
                                .accessibilityIdentifier("cameraSettings.lens")
                        }
                    }
                    section(Text("Selfie window", bundle: .module)) {
                        SegmentedControl(selection: $settings.selfieWindow.corner, options: CameraSettings.SelfieWindow.Corner.allCases, fitsLabels: true) {
                            Text($0.title)
                        }
                        .accessibilityIdentifier("cameraSettings.corner")
                        SegmentedControl(selection: $settings.selfieWindow.scale, options: CameraSettings.SelfieWindow.Scale.allCases) { Text($0.title) }
                            .accessibilityIdentifier("cameraSettings.size")
                    }
                    section(Text("Opens in", bundle: .module)) {
                        SegmentedControl(selection: $settings.opensIn, options: CameraSettings.Mode.allCases) { $0.label }
                    }
                    section(Text("Video length", bundle: .module)) {
                        SegmentedControl(selection: $settings.videoLength, options: CameraSettings.VideoLength.allCases) {
                            Text($0.settingsLabel)
                        }
                    }
                    VStack(spacing: 0) {
                        toggle(Text("Record sound", bundle: .module), isOn: $settings.recordsSound, id: "cameraSettings.sound")
                        Rectangle().fill(ColorToken.separator.color).frame(height: 1).padding(.leading, 16)
                        toggle(Text("Shutter sound", bundle: .module), detail: Text("In silent mode, photos never make a sound.", bundle: .module), isOn: $settings.cameraSounds, id: "cameraSettings.shutter")
                    }
                    .background(ColorToken.surfaceCard.color, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .padding(.top, 12)
                }
                .padding(.horizontal, Spacing.screenMargin)
                .padding(.top, 8)
            }
            .background(ColorToken.surfaceSheet.color.ignoresSafeArea())
            .navigationTitle(Text("Camera", bundle: .module))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Text("Done", bundle: .module) }
                        .accessibilityIdentifier("cameraSettings.done")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func section(_ title: Text, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            title
                .textStyle(.labelCaps)
                .foregroundStyle(ColorToken.textSecondary.color)
                .accessibilityAddTraits(.isHeader)
            content()
        }
        .padding(.top, 8)
    }

    private func toggle(_ title: Text, detail: Text? = nil, isOn: Binding<Bool>, id: String) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                title
                    .textStyle(.rowTitle)
                    .foregroundStyle(ColorToken.textPrimary.color)
                if let detail {
                    detail
                        .textStyle(.meta)
                        .foregroundStyle(ColorToken.textSecondary.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .tint(ColorToken.actionCoral.color)
        .padding(.horizontal, 16)
        .padding(.vertical, detail == nil ? 0 : 10)
        .frame(minHeight: 52)
        .accessibilityIdentifier(id)
    }
}

extension CameraSettings.Mode {
    var label: Text {
        switch self {
        case .photo: Text("Photo", bundle: .module)
        case .video: Text("Video", bundle: .module)
        }
    }
}

extension CameraSettings.VideoLength {
    var settingsLabel: LocalizedStringResource {
        LocalizedStringResource("\(rawValue) s", bundle: .atURL(Bundle.module.bundleURL))
    }
}
