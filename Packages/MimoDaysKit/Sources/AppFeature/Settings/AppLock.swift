import Foundation
import LocalAuthentication
import Observation

/// S05 App Lock: MimoDays asks for Face ID (or the passcode) at launch and after being away for the chosen time.
@MainActor
@Observable
final class AppLock {
    /// What unlocks this iPhone, for the words on the switch and the lock screen.
    enum Biometry: Sendable {
        case faceID
        case touchID
        case opticID
        case passcode

        static var current: Biometry {
            let context = LAContext()
            _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
            switch context.biometryType {
            case .faceID: return .faceID
            case .touchID: return .touchID
            case .opticID: return .opticID
            default: return .passcode
            }
        }
    }

    /// Asks the owner to prove it's them; true when they did.
    typealias Authenticate = @MainActor (_ reason: String) async -> Bool

    let biometry: Biometry
    /// True while MimoDays is covered by the lock screen.
    private(set) var isLocked: Bool
    /// True while Face ID (or the passcode sheet) is up.
    private(set) var isAuthenticating = false

    @ObservationIgnored private let settings: @MainActor () -> PrivacySettings
    @ObservationIgnored private let authenticate: Authenticate
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var leftAt: Date?
    /// Set at launch and on leaving; Face ID's own sheet also makes the app inactive, and coming back from it mustn't ask again.
    @ObservationIgnored private var asksOnActive = true

    init(
        settings: @escaping @MainActor () -> PrivacySettings,
        biometry: Biometry = .current,
        authenticate: @escaping Authenticate = AppLock.deviceOwner,
        now: @escaping () -> Date = Date.init
    ) {
        self.settings = settings
        self.biometry = biometry
        self.authenticate = authenticate
        self.now = now
        isLocked = settings().appLock
    }

    var isEnabled: Bool { settings().appLock }

    /// MimoDays went to the background. "Leaving the app" covers it at once, so the app switcher shows nothing.
    func didEnterBackground() {
        guard isEnabled else { return }
        leftAt = now()
        asksOnActive = true
        if settings().lockAfter == .immediately { isLocked = true }
    }

    /// Back from the background: away long enough, it locks and asks straight away.
    func didBecomeActive() async {
        guard isEnabled else {
            isLocked = false
            return
        }
        if let leftAt, now().timeIntervalSince(leftAt) >= settings().lockAfter.seconds { isLocked = true }
        leftAt = nil
        // After a failed Face ID the lock screen's button asks again.
        guard asksOnActive else { return }
        asksOnActive = false
        await unlock()
    }

    /// The lock screen's button, and the first ask at launch.
    func unlock() async {
        guard isLocked, !isAuthenticating else { return }
        if await confirm(String(localized: "Unlock MimoDays", bundle: .module, comment: "Why Face ID is asked for: to open the locked app")) {
            isLocked = false
        }
    }

    /// Face ID for one thing: turning App Lock on, opening Recently deleted, deleting everything.
    func confirm(_ reason: String) async -> Bool {
        guard !isAuthenticating else { return false }
        isAuthenticating = true
        defer { isAuthenticating = false }
        return await authenticate(reason)
    }

    /// Face ID, Touch ID or Optic ID, falling back to the passcode.
    static func deviceOwner(_ reason: String) async -> Bool {
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else { return false }
        return (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
    }
}

extension AppLock.Biometry {
    /// "Face ID", or "your passcode" on an iPhone without biometrics.
    var name: String {
        switch self {
        case .faceID: "Face ID"
        case .touchID: "Touch ID"
        case .opticID: "Optic ID"
        case .passcode: String(localized: "your passcode", bundle: .module, comment: "What unlocks the app when the iPhone has no Face ID, as in 'Lock with your passcode'")
        }
    }
}
