import Core
import DesignSystem
import SwiftUI

/// S03 with the app's settings store; the camera reads them the next time it opens.
struct CameraSettingsScreen: View {
    @Environment(\.camera) private var services
    @Environment(\.permissions) private var permissions
    @State private var settings: CameraSettings?
    @State private var access = CameraSettingsView.Access.notAsked

    var body: some View {
        Group {
            if let services, let settings {
                CameraSettingsView(
                    settings: Binding { settings } set: { self.settings = $0; services.settings.save($0) },
                    access: access,
                    sizeRates: services.videoSizes.rates()
                )
            } else {
                // An empty group never appears, so its task would never load the settings.
                ColorToken.canvas.color.ignoresSafeArea()
            }
        }
        .task {
            settings = services?.settings.load()
            access = await CameraSettingsView.Access(
                camera: permissions.status(of: .camera), microphone: permissions.status(of: .microphone)
            )
        }
    }
}

/// S03: how the camera opens, how long videos run, their quality, the selfie window, sound, and access.
struct CameraSettingsView: View {
    /// The Permissions row's value.
    enum Access {
        case allowed
        case cameraOnly
        case off
        case notAsked

        init(camera: PermissionStatus, microphone: PermissionStatus) {
            switch camera {
            case .granted, .limited: self = microphone.isUsable ? .allowed : .cameraOnly
            case .denied, .restricted: self = .off
            case .notDetermined: self = .notAsked
            }
        }
    }

    @Binding var settings: CameraSettings
    let access: Access
    /// P3.4: what each video size took on this phone.
    var sizeRates: [VideoSize: VideoSizeMeter.Rate] = [:]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 0) {
            BackTitleBar(back: Text("Settings", bundle: .module), title: Text("Camera", bundle: .module)) { dismiss() }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    sectionLabel(Text("Opens in", bundle: .module))
                    SegmentedControl(selection: $settings.opensIn, options: CameraSettings.Mode.allCases) { $0.label }
                        .padding(.top, 6)
                        .padding(.horizontal, 20)
                        .accessibilityIdentifier("cameraSettings.opensIn")
                    sectionLabel(Text("Video length", bundle: .module))
                        .padding(.top, 16)
                    SegmentedControl(selection: $settings.videoLength, options: CameraSettings.VideoLength.allCases) { Text($0.settingsLabel) }
                        .padding(.top, 6)
                        .padding(.horizontal, 20)
                        .accessibilityIdentifier("cameraSettings.length")
                    // X01.
                    sectionLabel(Text("Video size", bundle: .module))
                        .padding(.top, 16)
                    VideoSizePicker(size: $settings.videoSize, rates: sizeRates)
                        .padding(.top, 6)
                        .padding(.horizontal, 20)
                    DataCard {
                        Menu {
                            Picker(selection: $settings.selfieWindow.corner) {
                                ForEach(CameraSettings.SelfieWindow.Corner.allCases, id: \.self) { Text($0.title).tag($0) }
                            } label: {
                                Text("Corner", bundle: .module)
                            }
                            Picker(selection: $settings.selfieWindow.scale) {
                                ForEach(CameraSettings.SelfieWindow.Scale.allCases, id: \.self) { Text($0.title).tag($0) }
                            } label: {
                                Text("Size", bundle: .module)
                            }
                        } label: {
                            SettingsValueRow(title: Text("Selfie window", bundle: .module), value: selfieWindowValue)
                        }
                        .accessibilityIdentifier("cameraSettings.window")
                        DataSeparator()
                        DataToggleRow(title: Text("Record sound", bundle: .module), isOn: $settings.recordsSound)
                            .accessibilityIdentifier("cameraSettings.sound")
                        DataSeparator()
                        DataToggleRow(title: Text("Shutter sound", bundle: .module), detail: Text("In silent mode, photos never make a sound.", bundle: .module), isOn: $settings.cameraSounds)
                            .accessibilityIdentifier("cameraSettings.shutter")
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 18)
                    DataCard {
                        Button {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        } label: {
                            DataIconRow(icon: .glyphGear, title: Text("Permissions", bundle: .module), value: accessValue)
                        }
                        .accessibilityIdentifier("cameraSettings.permissions")
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 18)
                    DataNote(text: Text("Opens iOS Settings for MimoDays.", bundle: .module))
                        .padding(.horizontal, 22)
                        .padding(.top, 12)
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
        .background(ColorToken.canvas.color.ignoresSafeArea())
    }

    private func sectionLabel(_ text: Text) -> some View {
        text.textStyle(.labelCaps)
            .foregroundStyle(ColorToken.textSecondary.color)
            .accessibilityAddTraits(.isHeader)
            .padding(.horizontal, 22)
    }

    /// "Top right, medium", joined the way the locale lists things.
    private var selfieWindowValue: Text {
        Text(verbatim: [String(appLocalized: settings.selfieWindow.corner.title), String(appLocalized: settings.selfieWindow.scale.inlineTitle)]
            .formatted(.list(type: .and, width: .narrow).locale(AppLanguage.shared.locale)))
    }

    private var accessValue: Text {
        switch access {
        case .allowed: Text("Allowed", bundle: .module)
        case .cameraOnly: Text("Camera only", bundle: .module)
        case .off: Text("Off", bundle: .module)
        case .notAsked: Text("Not asked yet", bundle: .module)
        }
    }
}

/// A title, its value in grey and a chevron: rows that open a menu or a screen.
struct SettingsValueRow: View {
    let title: Text
    let value: Text

    var body: some View {
        HStack(spacing: 6) {
            title.textStyle(.rowTitle).foregroundStyle(ColorToken.textPrimary.color)
            Spacer(minLength: 8)
            value.textStyle(.rowDetail).foregroundStyle(ColorToken.textTertiary.color)
            DataChevron()
        }
        .padding(.leading, 16)
        .padding(.trailing, 14)
        .frame(minHeight: Size.rowHeight)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

extension VideoSize {
    /// X01/X02: the segment names.
    var label: Text {
        switch self {
        case .high: Text("High", bundle: .module, comment: "Video size (P3.4): today's size, the default")
        case .balanced: Text("Balanced", bundle: .module, comment: "Video size (P3.4): 1080p at a lower bit rate")
        case .compact: Text("Compact", bundle: .module, comment: "Video size (P3.4): the smallest videos")
        }
    }
}

extension CameraSettings.SelfieWindow.Scale {
    /// The size inside a sentence: "Top right, medium".
    var inlineTitle: LocalizedStringResource {
        switch self {
        case .small: LocalizedStringResource("Selfie window size in a phrase: small", defaultValue: "small", bundle: .atURL(Bundle.module.bundleURL))
        case .medium: LocalizedStringResource("Selfie window size in a phrase: medium", defaultValue: "medium", bundle: .atURL(Bundle.module.bundleURL))
        case .large: LocalizedStringResource("Selfie window size in a phrase: large", defaultValue: "large", bundle: .atURL(Bundle.module.bundleURL))
        }
    }
}
