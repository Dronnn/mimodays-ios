@testable import AppFeature
import Foundation
import Synchronization
import Testing

@MainActor
@Suite(.serialized)
struct CameraShortcutTests {
    /// Repeated triggers before the app takes them are one camera; a request is taken once.
    @Test func repeatedTriggersAreOneRequestTakenOnce() {
        _ = CameraShortcut.take()
        #expect(!CameraShortcut.take())
        CameraShortcut.request()
        CameraShortcut.request()
        #expect(CameraShortcut.take())
        #expect(!CameraShortcut.take())
    }

    /// RootView hears a request while it's up.
    @Test func aRequestIsAnnounced() async {
        _ = CameraShortcut.take()
        let heard = Mutex(0)
        let observer = NotificationCenter.default.addObserver(forName: CameraShortcut.requested, object: nil, queue: nil) { _ in heard.withLock { $0 += 1 } }
        CameraShortcut.request()
        NotificationCenter.default.removeObserver(observer)
        #expect(heard.withLock { $0 } == 1)
        #expect(CameraShortcut.take())
    }

    /// iPad windows: one in the background leaves the request to one in front; a camera up anywhere spends it.
    @Test func onlyAWindowInFrontWithNoCameraUpTakesIt() {
        _ = CameraShortcut.take()
        CameraShortcut.request()
        #expect(!CameraShortcut.take(inBackground: true))
        CameraShortcut.openCameras = 1
        #expect(!CameraShortcut.take())
        #expect(!CameraShortcut.isPending)
        CameraShortcut.openCameras = 0
        CameraShortcut.request()
        #expect(CameraShortcut.take())
    }

    /// The camera route a shortcut opens: no prompt, so never a surprise.
    @Test func itOpensAPlainCamera() {
        #expect(CameraShortcut.route == .capture(promptID: nil))
    }
}
