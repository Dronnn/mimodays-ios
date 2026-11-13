import Core
import DesignSystem
import SwiftUI

/// The explainers shown before a system prompt, and the screen shown once access is off.
enum PermissionScreen: CaseIterable {
    /// C06: before the camera prompt.
    case camera
    /// C06c: before the microphone prompt, on the first video.
    case microphone
    /// C13a: camera access is off; only Settings can turn it back on.
    case cameraOff

    var glyph: Icon {
        switch self {
        case .camera: .explainerCamera
        case .microphone: .explainerMicrophone
        case .cameraOff: .explainerCameraOff
        }
    }

    var title: LocalizedStringResource {
        switch self {
        case .camera: LocalizedStringResource("Let MimoDays use the camera", bundle: .atURL(Bundle.module.bundleURL))
        case .microphone: LocalizedStringResource("Add sound to your videos?", bundle: .atURL(Bundle.module.bundleURL))
        case .cameraOff: LocalizedStringResource("The camera is turned off for MimoDays", bundle: .atURL(Bundle.module.bundleURL))
        }
    }

    var message: LocalizedStringResource {
        switch self {
        case .camera:
            LocalizedStringResource(
                "The camera turns on only while this screen is open, and only you start a recording. Nothing is captured in the background or sent anywhere.",
                bundle: .atURL(Bundle.module.bundleURL)
            )
        case .microphone:
            LocalizedStringResource(
                "The microphone records only while you are recording a video or a voice note. You can say no: videos are still saved, just silent.",
                bundle: .atURL(Bundle.module.bundleURL)
            )
        case .cameraOff:
            LocalizedStringResource(
                "To capture moments, allow camera access in Settings. You can still write notes and record voice notes from Today.",
                bundle: .atURL(Bundle.module.bundleURL)
            )
        }
    }

    var primaryAction: LocalizedStringResource {
        switch self {
        case .camera, .microphone: LocalizedStringResource("Continue", bundle: .atURL(Bundle.module.bundleURL))
        case .cameraOff: LocalizedStringResource("Open Settings", bundle: .atURL(Bundle.module.bundleURL))
        }
    }

    var secondaryAction: LocalizedStringResource {
        switch self {
        case .camera, .cameraOff: LocalizedStringResource("Not now", bundle: .atURL(Bundle.module.bundleURL))
        case .microphone: LocalizedStringResource("Record without sound", bundle: .atURL(Bundle.module.bundleURL))
        }
    }

    /// Explainers keep their buttons at the bottom; the "turned off" screen keeps them under the text.
    var pinsActions: Bool { self != .cameraOff }
}

/// Layout of C06 / C06c / C13a. The system prompt itself is never drawn.
struct PermissionExplainerView: View {
    let screen: PermissionScreen
    let primary: () -> Void
    let secondary: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ExplainerArt(glyph: screen.glyph)
                    .padding(.top, screen.pinsActions ? 108 : 118)
                Text(screen.title)
                    .textStyle(.displaySheet)
                    .foregroundStyle(ColorToken.textPrimary.color)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, 30)
                    .padding(.horizontal, 52)
                Text(screen.message)
                    .textStyle(.body)
                    .foregroundStyle(ColorToken.textBody.color)
                    .padding(.top, screen.pinsActions ? 22 : 18)
                    .padding(.horizontal, 52)
                if !screen.pinsActions {
                    actions.padding(.top, 28)
                }
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: Self.columnWidth)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if screen.pinsActions {
                actions
                    .padding(.top, 12)
                    .padding(.bottom, 30)
                    .background(ColorToken.canvas.color.ignoresSafeArea(edges: .bottom))
            }
        }
        .background(ColorToken.canvas.color.ignoresSafeArea())
    }

    private var actions: some View {
        VStack(spacing: 12) {
            Button(action: primary) { Text(screen.primaryAction) }
                .buttonStyle(.primary)
                .accessibilityIdentifier("permission.primary")
            Button(action: secondary) { Text(screen.secondaryAction) }
                .buttonStyle(.text)
                .accessibilityIdentifier("permission.secondary")
        }
        .padding(.horizontal, Spacing.screenMargin)
        .frame(maxWidth: Self.columnWidth)
    }

    /// The iPhone frame width; iPad keeps the same column (no separate iPad design).
    private static let columnWidth: CGFloat = 402
}

/// What the camera needs before it can open.
enum CameraAccessStep: Equatable {
    case explain
    case openSettings
    case camera

    init(_ status: PermissionStatus) {
        if status.isUsable {
            self = .camera
        } else if status.needsSettings {
            self = .openSettings
        } else {
            self = .explain
        }
    }
}

extension EnvironmentValues {
    @Entry var permissions: any PermissionService = SystemPermissionService()
}
