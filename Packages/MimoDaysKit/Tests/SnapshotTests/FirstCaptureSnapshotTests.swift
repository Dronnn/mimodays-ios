@testable import AppFeature
import Foundation
import Testing
import TestSupport

@MainActor
@Suite(.tags(.snapshot))
struct FirstCaptureSnapshotTests {
    @Test func invitation() {
        assertScreenSnapshots(of: FirstCaptureView(capture: {}, later: {}))
    }

    /// 2026-11-13 16:12 UTC: "Today, 4:12 PM" in the pinned snapshot locale.
    @Test func firstMoment() {
        let moment = SavedMoment(photo: .placeholder, selfie: .placeholder, capturedAt: Date(timeIntervalSince1970: 1_794_586_320))
        assertScreenSnapshots(of: FirstMomentView(moment: moment, viewMoments: {}, done: {}))
    }

    @Test func firstMomentWithoutSelfie() {
        let moment = SavedMoment(photo: .placeholder, selfie: nil, capturedAt: Date(timeIntervalSince1970: 1_794_586_320))
        assertScreenSnapshots(of: FirstMomentView(moment: moment, viewMoments: {}, done: {}), variants: [SnapshotVariant(.iPhone, .light)])
    }
}
