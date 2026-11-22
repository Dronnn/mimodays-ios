@testable import AppFeature
@testable import Core
import Foundation
import SwiftUI
import Testing
import TestSupport

/// P8.12 DD04, DD05 and the nothing-to-add state.
@MainActor
@Suite(.tags(.snapshot))
struct JournalingSnapshotTests {
    private func sheet(_ fixture: LaunchConfiguration.JournalingFixture, choose photo: Int? = nil) async throws -> JournalingSheet {
        let pick = try fixture.pick()
        let model = JournalingModel { pick }
        await model.start()
        model.chosen = photo ?? model.chosen
        return JournalingSheet(model: model) { _ in }
    }

    /// DD04: three photos, the second chosen.
    @Test func journalingPhotoChoice() async throws {
        assertScreenSnapshots(of: try await sheet(.photos, choose: 1), variants: SnapshotVariant.standard + SnapshotVariant.languages)
    }

    /// Photos and a prompt: Use a photo or Write from this prompt.
    @Test func journalingBoth() async throws {
        assertScreenSnapshots(of: try await sheet(.both), variants: [
            SnapshotVariant(.iPhone, .light), SnapshotVariant(.iPhone, .light, .accessibilityExtraLarge), SnapshotVariant(.iPhone, .light, rightToLeft: true),
        ])
    }

    @Test func journalingUnsupported() async throws {
        assertScreenSnapshots(of: try await sheet(.nothing), variants: [
            SnapshotVariant(.iPhone, .light), SnapshotVariant(.iPhone, .dark), SnapshotVariant(.iPhone, .light, .accessibilityExtraLarge),
        ] + SnapshotVariant.languages)
    }

    /// DD05: Write a moment with the suggestion's prompt as the hint.
    @Test func journalingWritingPrompt() {
        let model = WriteMomentModel(
            now: CaptureTime(instant: Date(timeIntervalSince1970: 1_794_407_820), timeZone: .gmt), drafts: nil, prompt: "What made you smile today?"
        )
        assertScreenSnapshots(of: WriteMomentView(model: model), variants: [
            SnapshotVariant(.iPhone, .light), SnapshotVariant(.iPhone, .dark), SnapshotVariant(.iPhone, .light, .accessibilityExtraLarge),
            SnapshotVariant(.iPhone, .light, rightToLeft: true),
        ] + SnapshotVariant.languages)
    }
}
