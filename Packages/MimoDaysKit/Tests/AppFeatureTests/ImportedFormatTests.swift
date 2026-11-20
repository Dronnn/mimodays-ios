@testable import AppFeature
import Core
import Foundation
import Persistence
import SwiftData
import Testing

/// Imports keep their own shape (Andrew, 2026-11-20).
@MainActor
struct ImportedFormatTests {
    @Test func theShapeFollowsThePicture() {
        #expect(CaptureFormat.fitting(width: 4032, height: 3024) == .landscape)
        #expect(CaptureFormat.fitting(width: 3024, height: 4032) == .portrait)
        #expect(CaptureFormat.fitting(width: 2000, height: 1900) == .square)
        // Stored wide, shown upright by EXIF 6.
        #expect(CaptureFormat.fitting(width: 4032, height: 3024, orientation: 6) == .portrait)
        #expect(CaptureFormat.fitting(width: 0, height: 0) == .portrait)
    }

    @Test func importsFromBeforeAreRepairedOnceAndCapturesStayAsTaken() throws {
        let container = try MimoDaysStore.makeContainer(inMemory: true)
        let context = container.mainContext
        func moment(_ origin: MomentOrigin, width: Int, height: Int) -> Moment {
            let moment = Moment(
                captured: CaptureTime(instant: .now, timeZoneID: "UTC"), origin: origin, mediaType: .photo, createdAt: .now
            )
            context.insert(moment)
            moment.media = [MomentMedia(role: .rearSource, relativePath: "a.jpg", uniformType: "public.jpeg", pixelWidth: width, pixelHeight: height, checksum: "x", byteCount: 1)]
            return moment
        }
        let wideImport = moment(.imported, width: 1920, height: 1080)
        let wideCapture = moment(.manual, width: 1920, height: 1080)
        try context.save()
        let defaults = try #require(UserDefaults(suiteName: "ImportedFormatTests-\(UUID().uuidString)"))

        ImportedFormats.repairOnce(context: context, defaults: defaults)
        #expect(wideImport.captureFormat == .landscape)
        #expect(wideCapture.captureFormat == .portrait)

        wideImport.captureFormat = .portrait
        ImportedFormats.repairOnce(context: context, defaults: defaults)
        #expect(wideImport.captureFormat == .portrait)
    }
}
