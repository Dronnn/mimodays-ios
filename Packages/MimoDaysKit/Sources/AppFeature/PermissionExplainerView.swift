import Core
import DesignSystem
import SwiftUI

/// The explainers shown before a system prompt, and the screen shown once access is off.
enum PermissionScreen: String, CaseIterable {
    /// C06: before the camera prompt.
    case camera
    /// C06c: before the microphone prompt, on the first video.
    case microphone
    /// C13a: camera access is off; only iOS Settings can turn it back on.
    case cameraOff
    /// Like C13a, when Voice note is tapped with the microphone off.
    case microphoneOff
    /// Before the microphone prompt from Voice note.
    case voiceNote
    /// Before the location prompt: a moment's place, or where I am on the map.
    case location
    /// Before the notifications prompt: surprises turned on in onboarding, on Today or in Settings.
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
                "To capture moments, allow camera access in iOS Settings.",
                bundle: .atURL(Bundle.module.bundleURL)
            )
        case .microphoneOff:
            LocalizedStringResource(
                "To record voice notes, allow microphone access in iOS Settings. You can still write a note.",
                bundle: .atURL(Bundle.module.bundleURL)
            )
        case .voiceNote:
            LocalizedStringResource(
                "The microphone records only while you are recording a voice note. Voice notes stay on your device.",
                bundle: .atURL(Bundle.module.bundleURL)
            )
        case .location:
            LocalizedStringResource(
                "MimoDays uses your location only while it is open: to add a place to a moment and to show where you are on the map. Places are kept on your device; to name them, MimoDays asks Apple's map service.",
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
        case .cameraOff, .microphoneOff: LocalizedStringResource("Open iOS Settings", bundle: .atURL(Bundle.module.bundleURL))
        }
    }

    /// Only the "turned off" screens have a way out: an explainer must always lead to the system prompt
    /// (App Review Guideline 5.1.1).
    var secondaryAction: LocalizedStringResource? {
        switch self {
        case .camera, .microphone, .voiceNote, .location, .notifications, .photos: nil
        case .cameraOff, .microphoneOff: LocalizedStringResource("Not now", bundle: .atURL(Bundle.module.bundleURL))
        }
    }

    /// Explainers keep their button at the bottom; the "turned off" screen keeps them under the text.
    var pinsActions: Bool { self != .cameraOff && self != .microphoneOff }
}

/// Layout of C06 / C06c / C13a. The system prompt itself is never drawn.
struct PermissionExplainerView: View {
    let screen: PermissionScreen
    let primary: () -> Void
    /// Not now on the "turned off" screens; explainers have no secondary action.
    var secondary: () -> Void = {}

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ExplainerArt(glyph: screen.glyph)
                    .padding(.top, screen.pinsActions ? 108 : 118)
                Text(screen.title)
                    .textStyle(.displaySheet)
                    .foregroundStyle(ColorToken.textPrimary.color)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("permission.\(screen.rawValue)")
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
            if let secondaryAction = screen.secondaryAction {
                Button(action: secondary) { Text(secondaryAction) }
                    .buttonStyle(.text)
                    .accessibilityIdentifier("permission.secondary")
            }
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
/// its Continue always leads to the system prompt, and nothing else does.
@MainActor @Observable
final class PermissionAsker {
    private(set) var screen: PermissionScreen?
    /// From a request until iOS has answered. Buttons that would present something else wait for it: a second
    /// explainer or a sheet presented meanwhile would be dropped.
    private(set) var isAsking = false
    @ObservationIgnored private var answer: CheckedContinuation<Bool, Never>?
    @ObservationIgnored private var continued = false
    @ObservationIgnored private var appeared = false
    @ObservationIgnored private var attempt = 0

    /// The status after the explainer and the system prompt; `screen` when the permission has a more specific one
    /// (the camera's microphone). A request while one is going on asks nothing and returns `.notDetermined`, like
    /// an explainer closed without Continue: a double tap on Save to Photos reached iOS directly.
    func request(_ permission: Permission, screen explainer: PermissionScreen? = nil, using service: any PermissionService) async -> PermissionStatus {
        guard !isAsking else { return .notDetermined }
        isAsking = true
        defer { isAsking = false }
        let status = await service.status(of: permission)
        guard status == .notDetermined else { return status }
        continued = false
        appeared = false
        attempt += 1
        let current = attempt
        screen = explainer ?? PermissionScreen(explaining: permission)
        let wentOn = await withCheckedContinuation { continuation in
            answer = continuation
            Task { await dropIfNotShown(current) }
        }
        // Closed some other way (its screen went away, or it never showed): iOS isn't asked.
        guard wentOn else { return await service.status(of: permission) }
        return await service.request(permission)
    }

    /// The explainer is on screen.
    func shown() {
        appeared = true
    }

    /// SwiftUI drops a presentation it can't make (another one on the way in or out). Without this the request
    /// would wait for ever and the screen's buttons with it.
    private func dropIfNotShown(_ request: Int) async {
        try? await Task.sleep(for: .seconds(2))
        guard request == attempt, !appeared, answer != nil else { return }
        dismissed()
    }

    /// Continue on the explainer: it starts to close.
    func proceed() {
        continued = true
        screen = nil
    }

    /// The explainer has finished closing. Only now does the request go on, so the system prompt (or the voice note's
    /// recording sheet) isn't presented while the explainer is still on screen or on its way out: the recording
    /// sheet was dropped at once and the recording stopped after a second (UI test, 2026-11-17).
    func dismissed() {
        screen = nil
        answer?.resume(returning: continued)
        answer = nil
        continued = false
    }
}

extension PermissionScreen: Identifiable {
    var id: Self { self }
}

extension View {
    /// Presents `asker`'s explainers over this view.
    func permissionExplainers(_ asker: PermissionAsker) -> some View {
        fullScreenCover(item: Binding { asker.screen } set: { _ in }, onDismiss: asker.dismissed) { screen in
            PermissionExplainerView(screen: screen) { asker.proceed() }
                .onAppear(perform: asker.shown)
        }
    }
}
