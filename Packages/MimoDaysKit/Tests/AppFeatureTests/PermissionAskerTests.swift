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
        asker.respond(true)
        #expect(await request.value == .granted)
        #expect(asker.screen == nil)
    }

    @Test func notNowLeavesItUndecided() async {
        let service = PresetPermissionService(status: .notDetermined)
        let asker = PermissionAsker()
        let request = Task { await asker.request(.location, using: service) }
        while asker.screen == nil { await Task.yield() }
        asker.respond(false)
        #expect(await request.value == .notDetermined)
        #expect(await service.status(of: .location) == .notDetermined)
    }

    @Test(arguments: [PermissionStatus.granted, .denied, .limited, .restricted])
    func anEarlierAnswerSkipsTheExplainer(_ status: PermissionStatus) async {
        let asker = PermissionAsker()
        #expect(await asker.request(.microphone, using: PresetPermissionService(status: status)) == status)
        #expect(asker.screen == nil)
    }
}
