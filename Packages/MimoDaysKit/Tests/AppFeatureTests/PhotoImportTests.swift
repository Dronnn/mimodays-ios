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
    private let container = try! TestStore.container()
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
    nonisolated fileprivate static let photo: Data = {
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

    /// Copies the photo into `folder` like the picker and notes in `log` that it was asked to. The slow one waits
    /// until cancelled; then it either still hands over its copy or fails, as a picker may.
    private struct Item: PhotoPickerItemLoading {
        let folder: URL
        let log: URL
        let name: String
        var slow = false
        var failsWhenCancelled = false
        /// An iCloud item whose download fails.
        var fails = false

        func loadFile() async throws -> PickedFile? {
            FileManager.default.createFile(atPath: log.appending(path: name).path, contents: nil)
            if fails { throw URLError(.networkConnectionLost) }
            if slow {
                // Long enough that only the close ends it, however slow the machine.
                try? await Task.sleep(for: .seconds(30))
                if failsWhenCancelled, Task.isCancelled { throw CancellationError() }
            }
            let url = folder.appending(path: "\(UUID().uuidString).jpg")
            try PhotoImportTests.photo.write(to: url)
            return PickedFile(url: url, isVideo: false)
        }
    }

    /// One picked item that won't download: the others come in, and Import says some didn't.
    @Test func anItemThatWontLoadIsReported() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "Picked-\(UUID().uuidString)", directoryHint: .isDirectory)
        let log = FileManager.default.temporaryDirectory.appending(path: "PickedLog-\(UUID().uuidString)", directoryHint: .isDirectory)
        for url in [folder, log] { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
        defer { for url in [folder, log] { try? FileManager.default.removeItem(at: url) } }
        let model = model()
        await model.load([Item(folder: folder, log: log, name: "here"), Item(folder: folder, log: log, name: "cloud", fails: true)])
        #expect(model.unreadable == 1)
        #expect(await !model.importAll())
        #expect(try moments().count == 1)
    }

    /// W2: closing the import while the picker still copies leaves no copy behind, and loads nothing more.
    @Test(arguments: [false, true])
    func closingMidLoadLeavesNoCopies(failsWhenCancelled: Bool) async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "Picked-\(UUID().uuidString)", directoryHint: .isDirectory)
        let log = FileManager.default.temporaryDirectory.appending(path: "PickedLog-\(UUID().uuidString)", directoryHint: .isDirectory)
        for url in [folder, log] { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
        defer { for url in [folder, log] { try? FileManager.default.removeItem(at: url) } }
        let model = model()
        model.start([
            Item(folder: folder, log: log, name: "first"),
            Item(folder: folder, log: log, name: "slow", slow: true, failsWhenCancelled: failsWhenCancelled),
            Item(folder: folder, log: log, name: "third"),
        ])
        let logged = { Set((try? FileManager.default.contentsOfDirectory(atPath: log.path)) ?? []) }
        // Closed while the slow one copies.
        for _ in 0..<100 where !logged().contains("slow") { try await Task.sleep(for: .milliseconds(50)) }
        try #require(logged() == ["first", "slow"])
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).count == 1)
        model.discard()
        // The slow copy lands (or fails) after the close; whatever came goes, and the third is never asked for.
        try await Task.sleep(for: .seconds(1.5))
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
        #expect(logged() == ["first", "slow"])
        #expect(model.picked.isEmpty)
    }

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
        // 64x48: a wide photo keeps its shape (Andrew, 2026-11-20).
        #expect(moment.captureFormat == .landscape)
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

    // MARK: Live Photos (P8.6)

    /// A Live Photo the picker handed over: the still and a short motion clip, in tmp.
    private func livePhoto(motion: Bool = true, broken: Bool = false) async throws -> PickedFile {
        var motionURL: URL?
        if broken {
            motionURL = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).mov")
            try Data("not a movie".utf8).write(to: motionURL!)
        } else if motion {
            let engine = SimulatedCaptureEngine()
            _ = await engine.start()
            let clip = try await engine.record(limit: .seconds(1.5))
            if let selfie = clip.selfieURL { try? FileManager.default.removeItem(at: selfie) }
            motionURL = clip.mainURL
        }
        return PickedFile(url: try picked(), isVideo: false, motionURL: motionURL, isLivePhoto: true)
    }

    /// One photo moment with its still and its motion; the copies in tmp go.
    @Test func aLivePhotoKeepsItsMotion() async throws {
        let file = try await livePhoto()
        let model = model()
        await model.load([file])
        #expect(model.livePhotos == 1 && model.motionFailed.isEmpty && model.new.count == 1)
        #expect(await model.importAll())
        let moment = try #require(try moments().first)
        #expect(try moments().count == 1)
        #expect(moment.mediaType == .photo && moment.origin == .imported)
        let motion = try #require(moment.livePhotoMotion)
        #expect((motion.duration ?? 0) > 1)
        #expect(FileManager.default.fileExists(atPath: try store.url(for: motion.relativePath).path))
        #expect(moment.media.contains { $0.role == .rearSource })
        #expect(!FileManager.default.fileExists(atPath: file.motionURL!.path))
    }

    /// Motion that didn't come, or won't play, is never dropped quietly: the item waits for Import as still or Skip.
    @Test(arguments: [(false, false), (true, false), (false, true)])
    func motionThatFailsAsksFirst(broken: Bool, skips: Bool) async throws {
        let model = model()
        await model.load([try await livePhoto(motion: broken, broken: broken)])
        #expect(model.motionFailed == [0])
        #expect(model.new.isEmpty)
        if skips { model.skip(0) } else { model.importAsStill(0) }
        #expect(model.motionFailed.isEmpty)
        #expect(model.new.map(\.id) == (skips ? [] : [0]))
        #expect(await model.importAll())
        let moments = try moments()
        #expect(moments.count == (skips ? 0 : 1) && moments.first?.livePhotoMotion == nil)
    }

    /// A Live Photo handed over first without its motion, then with it.
    private final class FlakyLivePhoto: PhotoPickerItemLoading, @unchecked Sendable {
        let first: PickedFile
        let second: PickedFile
        private var calls = 0

        init(first: PickedFile, second: PickedFile) {
            self.first = first
            self.second = second
        }

        func loadFile() async throws -> PickedFile? {
            calls += 1
            return calls == 1 ? first : second
        }
    }

    /// EE05 Try again: the motion that didn't come comes now; the item is ready with it and imports as one moment.
    @Test func tryAgainBringsTheMotion() async throws {
        let item = FlakyLivePhoto(first: try await livePhoto(motion: false), second: try await livePhoto())
        let model = model()
        await model.load([item])
        #expect(model.motionFailed == [0] && model.new.isEmpty)
        await model.retryMotion()
        #expect(model.motionFailed.isEmpty && model.new.count == 1)
        #expect(model.picked.first?.motionURL != nil)
        #expect(await model.importAll())
        #expect(try moments().first?.livePhotoMotion != nil)
    }

    /// The still is here already without motion: skipped as usual, and Keep motion adds it to that moment.
    @Test func keepMotionJoinsTheMomentAlreadyHere() async throws {
        let first = model()
        await first.load([(try picked(), false)])
        #expect(await first.importAll())
        let second = model()
        await second.load([try await livePhoto()])
        #expect(second.skipped == [0] && second.new.isEmpty)
        let here = try #require(try moments().first)
        #expect(second.motionToAttach == [0: here.id])
        #expect(await second.attachMotion(0))
        #expect(try moments().count == 1)
        #expect(here.livePhotoMotion != nil)
        #expect(second.motionToAttach.isEmpty)
        // Picked once more: it has its motion now, so nothing is offered.
        let again = model()
        await again.load([try await livePhoto()])
        #expect(again.skipped == [0] && again.motionToAttach.isEmpty)
    }

    /// A backup with a Live Photo needs version 2; its motion comes back with it.
    @Test func aLivePhotoNeedsBackupVersionTwo() async throws {
        let model = model()
        await model.load([try await livePhoto()])
        #expect(await model.importAll())
        let moment = try #require(try moments().first)
        var document = BackupDocument(createdAt: Date())
        document.moments = [BackupDocument.MomentRecord(moment)]
        #expect(document.neededVersion == BackupDocument.currentVersion)
        document.moments[0].media.removeAll { $0.role == MediaRole.livePhotoMotion.rawValue }
        #expect(document.neededVersion == BackupDocument.firstVersion)
    }

    /// The picker's bundle: its still and its movie, both needed.
    @Test func aBundleGivesTheStillAndTheMotion() throws {
        let bundle = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).pvt", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: bundle) }
        try Self.photo.write(to: bundle.appending(path: "IMG_0001.JPG"))
        try Data("movie".utf8).write(to: bundle.appending(path: "IMG_0001.MOV"))
        let file = try LivePhotoFiles.split(bundle: bundle)
        #expect(file.isLivePhoto && !file.isVideo)
        #expect(try Data(contentsOf: file.url) == Self.photo)
        #expect(try Data(contentsOf: try #require(file.motionURL)) == Data("movie".utf8))
        try FileManager.default.removeItem(at: bundle.appending(path: "IMG_0001.MOV"))
        #expect(throws: LivePhotoFiles.Failure.incomplete) { try LivePhotoFiles.split(bundle: bundle) }
    }
}
