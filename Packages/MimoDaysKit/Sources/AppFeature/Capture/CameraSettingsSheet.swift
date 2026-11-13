import DesignSystem
import SwiftUI

/// The camera's ••• sheet: the S03 camera settings without leaving the camera (Andrew, 2026-11-13).
struct CameraSettingsSheet: View {
    @Binding var settings: CameraSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
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
                        toggle(Text("Camera sounds", bundle: .module), isOn: $settings.cameraSounds, id: "cameraSettings.shutter")
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

    private func toggle(_ title: Text, isOn: Binding<Bool>, id: String) -> some View {
        Toggle(isOn: isOn) {
            title
                .textStyle(.rowTitle)
                .foregroundStyle(ColorToken.textPrimary.color)
        }
        .tint(ColorToken.actionCoral.color)
        .padding(.horizontal, 16)
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
