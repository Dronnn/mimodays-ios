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
    /// Like C13a, when Voice note is tapped with the microphone off.
    case microphoneOff
    /// Before the microphone prompt from Voice note.
    case voiceNote
    /// Before the location prompt: a moment's place, or where I am on the map.
    case location
    /// Before the notifications prompt when surprises are turned on outside onboarding.
    case notifications
    /// Before the add-only Photos prompt on the first save to Photos.
    case photos

    /// Our explainer for a system prompt (Andrew, 2026-11-17: every prompt gets one).
    init(explaining permission: Permission) {
        switch permission {
        case .camera: self = .camera
        case .microphone: self = .voiceNote
        case .location: self = .location
        case .notifications: self = .notifications
        case .photoLibrary: self = .photos
        }
    }

    var glyph: Icon {
        switch self {
        case .camera: .explainerCamera
        case .microphone: .explainerMicrophone
        case .cameraOff: .explainerCameraOff
        case .microphoneOff, .voiceNote: .explainerMicrophone
        case .location: .explainerPin
        case .notifications: .explainerBell
        case .photos: .explainerPhotos
        }
    }

    var title: LocalizedStringResource {
        switch self {
        case .camera: LocalizedStringResource("Let MimoDays use the camera", bundle: .atURL(Bundle.module.bundleURL))
        case .microphone: LocalizedStringResource("Add sound to your videos?", bundle: .atURL(Bundle.module.bundleURL))
        case .cameraOff: LocalizedStringResource("The camera is turned off for MimoDays", bundle: .atURL(Bundle.module.bundleURL))
        case .microphoneOff: LocalizedStringResource("The microphone is turned off for MimoDays", bundle: .atURL(Bundle.module.bundleURL))
        case .voiceNote: LocalizedStringResource("Say a few words?", bundle: .atURL(Bundle.module.bundleURL))
        case .location: LocalizedStringResource("Remember where it happened?", bundle: .atURL(Bundle.module.bundleURL))
        case .notifications: LocalizedStringResource("Get a little surprise?", bundle: .atURL(Bundle.module.bundleURL))
        case .photos: LocalizedStringResource("Save to your photos?", bundle: .atURL(Bundle.module.bundleURL))
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
        case .microphoneOff:
            LocalizedStringResource(
                "To record voice notes, allow microphone access in Settings. You can still write a note.",
                bundle: .atURL(Bundle.module.bundleURL)
            )
        case .voiceNote:
            LocalizedStringResource(
                "The microphone records only while you are recording a voice note. Voice notes stay on your device.",
                bundle: .atURL(Bundle.module.bundleURL)
            )
        case .location:
            LocalizedStringResource(
                "MimoDays uses your location only while it is open: to add a place to a moment and to show where you are on the map. It stays on your device.",
                bundle: .atURL(Bundle.module.bundleURL)
            )
        case .notifications:
            LocalizedStringResource(
                "Now and then, at a random time within your hours, MimoDays sends one notification to catch the moment. No streaks, no nagging. Pause or turn it off any time.",
                bundle: .atURL(Bundle.module.bundleURL)
            )
        case .photos:
            LocalizedStringResource(
                "MimoDays only adds what you save. It can't see the rest of your library.",
                bundle: .atURL(Bundle.module.bundleURL)
            )
        }
    }

    var primaryAction: LocalizedStringResource {
        switch self {
        case .camera, .microphone, .voiceNote, .location, .notifications, .photos: LocalizedStringResource("Continue", bundle: .atURL(Bundle.module.bundleURL))
        case .cameraOff, .microphoneOff: LocalizedStringResource("Open Settings", bundle: .atURL(Bundle.module.bundleURL))
        }
    }

    var secondaryAction: LocalizedStringResource {
        switch self {
        case .camera, .cameraOff, .microphoneOff, .voiceNote, .location, .notifications, .photos: LocalizedStringResource("Not now", bundle: .atURL(Bundle.module.bundleURL))
        case .microphone: LocalizedStringResource("Record without sound", bundle: .atURL(Bundle.module.bundleURL))
        }
    }

    /// Explainers keep their buttons at the bottom; the "turned off" screen keeps them under the text.
    var pinsActions: Bool { self != .cameraOff && self != .microphoneOff }
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

/// Our explainer before a system prompt, for screens that ask on a tap. Shown only while iOS hasn't asked yet;
/// "Not now" leaves the permission undecided, so the next tap explains again.
@MainActor @Observable
final class PermissionAsker {
    private(set) var screen: PermissionScreen?
    @ObservationIgnored private var answer: CheckedContinuation<Bool, Never>?

    /// The status after the explainer and the system prompt; `.notDetermined` after "Not now".
    func request(_ permission: Permission, using service: any PermissionService) async -> PermissionStatus {
        let status = await service.status(of: permission)
        guard status == .notDetermined, answer == nil else { return status }
        screen = PermissionScreen(explaining: permission)
        let goesOn = await withCheckedContinuation { answer = $0 }
        return goesOn ? await service.request(permission) : .notDetermined
    }

    /// Continue (true) or Not now (false) on the explainer.
    func respond(_ goesOn: Bool) {
        screen = nil
        answer?.resume(returning: goesOn)
        answer = nil
    }
}

extension PermissionScreen: Identifiable {
    var id: Self { self }
}

extension View {
    /// Presents `asker`'s explainers over this view.
    func permissionExplainers(_ asker: PermissionAsker) -> some View {
        fullScreenCover(item: Binding { asker.screen } set: { if $0 == nil { asker.respond(false) } }) { screen in
            PermissionExplainerView(screen: screen) { asker.respond(true) } secondary: { asker.respond(false) }
        }
    }
}
