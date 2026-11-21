@testable import AppFeature
import Foundation
import Synchronization
import Testing
import UIKit

/// A Photos library for one day, its access and failures set by the test.
final class FakePhotoDayLibrary: PhotoDayLibrary {
    private let state: Mutex<(access: PhotoDayAccess, answer: PhotoDayAccess, assets: [PhotoDayAsset], fails: Bool, asked: Int)>

    init(access: PhotoDayAccess = .full, answer: PhotoDayAccess = .full, assets: [PhotoDayAsset] = [], fails: Bool = false) {
        state = Mutex((access, answer, assets, fails, 0))
    }

    var asked: Int { state.withLock { $0.asked } }
    func setFails(_ fails: Bool) { state.withLock { $0.fails = fails } }

    func access() -> PhotoDayAccess { state.withLock { $0.access } }

    func requestAccess() async -> PhotoDayAccess {
        state.withLock {
            $0.asked += 1
            $0.access = $0.answer
            return $0.answer
        }
    }

    func assets(on day: Int) async throws -> [PhotoDayAsset] {
        try state.withLock {
            if $0.fails { throw URLError(.cannotOpenFile) }
            return $0.assets
        }
    }

    func thumbnail(_ id: String) async -> UIImage? { nil }
    func file(_ id: String) async throws -> PickedFile? { nil }

    static func assets(_ count: Int) -> [PhotoDayAsset] {
        (0..<count).map {
            PhotoDayAsset(
                id: "asset-\($0)", createdAt: Date(timeIntervalSince1970: 1_795_250_000 - Double($0) * 3_600),
                isVideo: $0 == 2, isLivePhoto: $0 == 1, duration: $0 == 2 ? 10 : 0
            )
        }
    }
}

/// P8.5: Find moments in Photos for an empty day.
@MainActor
struct PhotoDayModelTests {
    /// Before iOS has asked: our explainer, then iOS, then the day.
    @Test func theExplainerComesFirst() async {
        let library = FakePhotoDayLibrary(access: .notDetermined, answer: .limited, assets: FakePhotoDayLibrary.assets(3))
        let model = PhotoDayModel(day: 20261121, library: library)
        await model.start()
        #expect(model.phase == .explainer && library.asked == 0)
        await model.requestAccess()
        #expect(library.asked == 1)
        #expect(model.phase == .ready && model.isLimited && model.assets.count == 3)
    }

    @Test func noToTheSystemPromptShowsTheWayToSettings() async {
        let model = PhotoDayModel(day: 20261121, library: FakePhotoDayLibrary(access: .notDetermined, answer: .denied))
        await model.start()
        await model.requestAccess()
        #expect(model.phase == .denied)
        let off = PhotoDayModel(day: 20261121, library: FakePhotoDayLibrary(access: .denied))
        await off.start()
        #expect(off.phase == .denied)
    }

    /// Nothing picked at first; Review takes the picked ones in the order shown.
    @Test func nothingIsPickedUntilTapped() async {
        let model = PhotoDayModel(day: 20261121, library: FakePhotoDayLibrary(assets: FakePhotoDayLibrary.assets(4)))
        await model.start()
        #expect(model.picked.isEmpty && model.items.isEmpty)
        model.toggle("asset-3")
        model.toggle("asset-1")
        model.toggle("asset-0")
        model.toggle("asset-0")
        #expect(model.items.map(\.id) == ["asset-1", "asset-3"])
    }

    @Test func anEmptyDayAndAFailureSaySo() async {
        let empty = PhotoDayModel(day: 20261121, library: FakePhotoDayLibrary())
        await empty.start()
        #expect(empty.phase == .empty)
        let library = FakePhotoDayLibrary(assets: FakePhotoDayLibrary.assets(2), fails: true)
        let model = PhotoDayModel(day: 20261121, library: library)
        await model.start()
        #expect(model.phase == .failed)
        library.setFails(false)
        await model.load()
        #expect(model.phase == .ready && model.assets.count == 2)
    }
}
