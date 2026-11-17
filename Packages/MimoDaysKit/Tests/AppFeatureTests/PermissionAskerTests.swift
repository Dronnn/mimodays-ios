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
        asker.proceed()
        #expect(asker.screen == nil)
        // The request goes on only once the explainer has finished closing.
        asker.dismissed()
        #expect(await request.value == .granted)
    }

    @Test(arguments: [PermissionStatus.granted, .denied, .limited, .restricted])
    func anEarlierAnswerSkipsTheExplainer(_ status: PermissionStatus) async {
        let asker = PermissionAsker()
        #expect(await asker.request(.microphone, using: PresetPermissionService(status: status)) == status)
        #expect(asker.screen == nil)
    }
}
