@testable import AppFeature
import Core
import Testing

/// Our explainer before every system prompt (Andrew, 2026-11-17).
@MainActor
struct PermissionAskerTests {
    @Test(arguments: Permission.allCases)
    func continueShowsTheSystemPrompt(_ permission: Permission) async {
        let service = PresetPermissionService(status: .notDetermined, requestResult: .granted)
        let asker = PermissionAsker()
        let request = Task { await asker.request(permission, using: service) }
        while asker.screen == nil { await Task.yield() }
        #expect(asker.screen == PermissionScreen(explaining: permission))
        asker.shown()
        asker.proceed()
        #expect(asker.screen == nil)
        // The request goes on only once the explainer has finished closing.
        asker.dismissed()
        #expect(await request.value == .granted)
    }

    /// A double tap, or a second button, while the explainer is up asks nothing: it never reaches iOS first.
    @Test func aSecondRequestWhileAskingAsksNothing() async {
        let service = PresetPermissionService(status: .notDetermined, requestResult: .granted)
        let asker = PermissionAsker()
        let first = Task { await asker.request(.photoLibrary, using: service) }
        while asker.screen == nil { await Task.yield() }
        asker.shown()
        #expect(asker.isAsking)
        #expect(await asker.request(.photoLibrary, using: service) == .notDetermined)
        #expect(await service.status(of: .photoLibrary) == .notDetermined)
        asker.proceed()
        asker.dismissed()
        #expect(await first.value == .granted)
        #expect(!asker.isAsking)
    }

    /// An explainer SwiftUI never showed gives up instead of keeping the screen's buttons waiting.
    @Test func anExplainerThatNeverShowsGivesUp() async {
        let asker = PermissionAsker()
        let status = await asker.request(.location, using: PresetPermissionService(status: .notDetermined))
        #expect(status == .notDetermined && !asker.isAsking && asker.screen == nil)
        // perm #3: the camera tries its microphone explainer again after one was dropped.
        #expect(asker.wasDropped)
    }

    @Test func theCameraNamesItsOwnMicrophoneExplainer() async {
        let asker = PermissionAsker()
        let request = Task { await asker.request(.microphone, screen: .microphone, using: PresetPermissionService(status: .notDetermined)) }
        while asker.screen == nil { await Task.yield() }
        #expect(asker.screen == .microphone)
        asker.shown()
        asker.proceed()
        asker.dismissed()
        _ = await request.value
    }

    /// Only Continue leads to the system prompt: an explainer closed with its screen asks nothing.
    @Test func closingWithoutContinueAsksNothing() async {
        let service = PresetPermissionService(status: .notDetermined, requestResult: .granted)
        let asker = PermissionAsker()
        let request = Task { await asker.request(.location, using: service) }
        while asker.screen == nil { await Task.yield() }
        asker.shown()
        asker.dismissed()
        #expect(await request.value == .notDetermined)
        #expect(!asker.wasDropped, "closed by the person, not dropped")
    }

    /// A dismissal of an explainer that was dropped before it showed doesn't answer the next request.
    @Test func aLateDismissalDoesntAnswerTheNextRequest() async {
        let service = PresetPermissionService(status: .notDetermined, requestResult: .granted)
        let asker = PermissionAsker()
        // Never shown: gives up after its two seconds.
        #expect(await asker.request(.location, using: service) == .notDetermined)
        let next = Task { await asker.request(.location, using: service) }
        while asker.screen == nil { await Task.yield() }
        asker.dismissed()
        #expect(asker.screen != nil)
        asker.shown()
        asker.proceed()
        asker.dismissed()
        #expect(await next.value == .granted)
    }

    @Test(arguments: [PermissionStatus.granted, .denied, .limited, .restricted])
    func anEarlierAnswerSkipsTheExplainer(_ status: PermissionStatus) async {
        let asker = PermissionAsker()
        #expect(await asker.request(.microphone, using: PresetPermissionService(status: status)) == status)
        #expect(asker.screen == nil)
    }
}
