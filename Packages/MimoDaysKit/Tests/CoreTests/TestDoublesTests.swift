import Core
import Foundation
import Testing
import TestSupport

struct TestDoublesTests {
    @Test func seededGeneratorRepeats() {
        var first = SeededRandomNumberGenerator(seed: 42)
        var second = SeededRandomNumberGenerator(seed: 42)
        let a = (0..<5).map { _ in Int.random(in: 0..<1000, using: &first) }
        let b = (0..<5).map { _ in Int.random(in: 0..<1000, using: &second) }
        #expect(a == b)
        #expect(Set(a).count > 1)
    }

    @Test func dateProviderMovesOnlyWhenTold() {
        let clock = TestDateProvider()
        let start = clock.now()
        #expect(clock.now() == start)
        clock.advance(by: 60)
        #expect(clock.now() == start.addingTimeInterval(60))
    }

    @Test func permissionRequestRecordsAndUpdatesStatus() async {
        let permissions = FakePermissionService(requestResults: [.camera: .denied])
        #expect(await permissions.status(of: .camera) == .notDetermined)
        #expect(await permissions.request(.camera) == .denied)
        #expect(await permissions.status(of: .camera) == .denied)
        #expect(await permissions.requested == [.camera])
    }

    @Test func notificationSchedulerReplacesByIDAndCancels() async throws {
        let scheduler = FakeNotificationScheduler()
        let date = Date(timeIntervalSince1970: 0)
        try await scheduler.schedule(SurpriseNotification(id: "a", fireDate: date))
        try await scheduler.schedule(SurpriseNotification(id: "a", fireDate: date.addingTimeInterval(10)))
        try await scheduler.schedule(SurpriseNotification(id: "b", fireDate: date))
        #expect(await scheduler.pending().map(\.id) == ["b", "a"])
        await scheduler.cancel(ids: ["a"])
        #expect(await scheduler.pending().map(\.id) == ["b"])
    }

    @Test func locationFailsWhenUnavailable() async {
        let location = FakeLocationProvider(location: nil)
        await #expect(throws: FakeServiceError.unavailable) { try await location.currentLocation() }
    }

    @Test func captureEngineFallsBackToSingleCamera() async {
        #expect(await FakeCaptureEngine(multiCam: false).capturePhoto().frontURL == nil)
        #expect(await FakeCaptureEngine(multiCam: true).capturePhoto().frontURL != nil)
    }
}
