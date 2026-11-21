@testable import AppFeature
@testable import Core
import DesignSystem
import Foundation
import Persistence
import SnapshotTesting
import SwiftUI
import Testing
import TestSupport

/// P8.11 II01, II02: Write a moment, empty and written.
@MainActor
@Suite(.tags(.snapshot))
struct WriteMomentSnapshotTests {
    /// Nov 11, 2026, 2:37 PM in the snapshot time zone.
    private let time = CaptureTime(instant: Date(timeIntervalSince1970: 1_794_407_820), timeZone: .gmt)

    private func model() -> WriteMomentModel {
        WriteMomentModel(now: time, drafts: nil)
    }

    /// II01 without the keyboard (it doesn't render in snapshots).
    @Test func writeMomentEmpty() {
        assertScreenSnapshots(of: WriteMomentView(model: model()), variants: [
            SnapshotVariant(.iPhone, .light), SnapshotVariant(.iPhone, .dark), SnapshotVariant(.iPhone, .light, .accessibilityExtraLarge),
        ] + SnapshotVariant.languages)
    }

    /// II02.
    @Test func writeMomentFilled() {
        let model = model()
        model.caption = "Rain day"
        model.body = "Lena and I built a blanket fort and read three chapters with a flashlight. She fell asleep before the dragon came back."
        model.choose(ReviewPlace(label: "Yerevan", latitude: 40.18, longitude: 44.51, precision: .city, source: .manual))
        model.tags = ["lena"]
        model.mood = .calm
        assertScreenSnapshots(of: WriteMomentView(model: model), variants: [
            SnapshotVariant(.iPhone, .light), SnapshotVariant(.iPhone, .dark), SnapshotVariant(.iPhone, .light, .accessibilityExtraLarge),
            SnapshotVariant(.iPhone, .light, rightToLeft: true), SnapshotVariant(.iPad, .light),
        ])
    }
}
