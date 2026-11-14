@testable import AppFeature
@testable import Core
import CoreGraphics
import Foundation
import ImageIO
import Persistence
import SwiftData
import Testing
import TestSupport
import UniformTypeIdentifiers

/// 12.6: picked files become moments on the day they were taken, marked imported, place only at city level
/// and only when kept; files already here are skipped.
@MainActor
@Suite(.serialized)
struct PhotoImportTests {
    private let container = try! MimoDaysStore.makeContainer(inMemory: true)
    private let store: MediaStore

    init() throws {
        store = try MediaStore(root: FileManager.default.temporaryDirectory.appending(path: "Import-\(UUID().uuidString)"))
    }

    private var library: MediaLibrary { MediaLibrary(context: container.mainContext, store: store, thumbnails: ThumbnailPipeline()) }

    private func model() -> PhotoImportModel {
        PhotoImportModel(
            library: library, saver: MomentSaver(context: container.mainContext, store: store, freeBytes: { nil }), lookup: SimulatedPlaceLookup()
        )
    }

    /// A small JPEG taken "2026:11:11 18:42:05" at +04:00, at the Cascade.
    private static let photo: Data = {
        let context = CGContext(
            data: nil, width: 64, height: 48, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(red: 0.8, green: 0.5, blue: 0.4, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 64, height: 48))
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)!
        let properties: [CFString: Any] = [
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifDateTimeOriginal: "2026:11:11 18:42:05", kCGImagePropertyExifOffsetTimeOriginal: "+04:00",
            ],
            kCGImagePropertyGPSDictionary: [
                kCGImagePropertyGPSLatitude: 40.19087, kCGImagePropertyGPSLatitudeRef: "N",
                kCGImagePropertyGPSLongitude: 44.51521, kCGImagePropertyGPSLongitudeRef: "E",
            ],
        ]
        CGImageDestinationAddImage(destination, context.makeImage()!, properties as CFDictionary)
        CGImageDestinationFinalize(destination)
        return data as Data
    }()

    /// What the picker hands over: a copy in tmp.
    private func picked() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).jpg")
        try Self.photo.write(to: url)
        return url
    }

    private func moments() throws -> [Moment] { try container.mainContext.fetch(FetchDescriptor<Moment>()) }

    @Test func aPhotoGoesToTheDayItWasTakenWithItsCity() async throws {
        let model = model()
        await model.load([(try picked(), false)])
        #expect(model.phase == .ready)
        #expect(model.new.count == 1)
        #expect(await model.importAll())
        let moment = try #require(try moments().first)
        #expect(moment.origin == .imported)
        #expect(moment.mediaType == .photo)
        #expect(moment.pipLayout == nil)
        // 18:42:05 at +04:00 is 14:42:05 UTC.
        #expect(moment.capturedAt == Date(timeIntervalSince1970: 1_794_408_125))
        #expect(TimeZone(identifier: moment.timeZoneID)?.secondsFromGMT() == 4 * 3600)
        let location = try #require(moment.location)
        #expect(location.precision == .city)
        #expect(location.source == .imported)
        #expect(location.placeLabel == "Yerevan")
        #expect(location.latitude == 40.19 && location.longitude == 44.52)
    }

    @Test func thePlaceStaysOutWhenNotKept() async throws {
        let model = model()
        await model.load([(try picked(), false)])
        model.keepsPlace = false
        #expect(await model.importAll())
        #expect(try moments().first?.location == nil)
    }

    @Test func filesAlreadyHereAreSkipped() async throws {
        let first = model()
        await first.load([(try picked(), false)])
        #expect(await first.importAll())
        let again = model()
        // The same photo picked again, twice.
        await again.load([(try picked(), false), (try picked(), false)])
        #expect(again.count == 2)
        #expect(again.skipped.count == 2)
        #expect(again.new.isEmpty)
        #expect(try moments().count == 1)
    }

    @Test func aPictureNotYetHereIsImportedNextToOneThatIs() async throws {
        let first = model()
        await first.load([(try picked(), false)])
        #expect(await first.importAll())
        let engine = SimulatedCaptureEngine()
        _ = await engine.start()
        let video = try await engine.record(limit: .seconds(1))
        let model = model()
        await model.load([(try picked(), false), (video.mainURL, true)])
        #expect(model.skipped.count == 1)
        #expect(model.videos == 1)
        #expect(model.new.map(\.isVideo) == [true])
        #expect(await model.importAll())
        let imported = try moments().filter { $0.mediaType == .video }
        #expect(imported.count == 1)
        #expect(imported.first?.origin == .imported)
        #expect((imported.first?.media.first { $0.role == .rearSource }?.duration ?? 0) > 0)
    }

    @Test func datesZonesAndPlacesAreReadFromTheFiles() throws {
        let exif = try #require(PhotoImportModel.captureTime(exif: "2026:11:11 18:42:05", offset: "-03:30"))
        #expect(exif.instant == Date(timeIntervalSince1970: 1_794_408_125 + 4 * 3600 + 3 * 3600 + 1800))
        #expect(exif.timeZone.secondsFromGMT() == -(3 * 3600 + 1800))
        let quickTime = try #require(PhotoImportModel.captureTime(iso8601: "2026-11-11T18:42:05+0400"))
        #expect(quickTime.instant == Date(timeIntervalSince1970: 1_794_408_125))
        #expect(quickTime.timeZone.secondsFromGMT() == 4 * 3600)
        let point = try #require(PhotoImportModel.point(iso6709: "+40.1811-074.0060+012.000/"))
        #expect(point.latitude == 40.1811 && point.longitude == -74.006)
        #expect(PhotoImportModel.captureTime(exif: nil, offset: nil) == nil)
        #expect(PhotoImportModel.point(gps: nil) == nil)
    }
}
