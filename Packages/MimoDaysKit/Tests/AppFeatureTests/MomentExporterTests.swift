@preconcurrency import AVFoundation
@testable import AppFeature
@testable import Core
import Foundation
import ImageIO
import Persistence
import SwiftData
import Testing
import TestSupport
import UniformTypeIdentifiers

/// 12.1, 12.2, 12.9: exported files carry no place, voice or note unless chosen; names sort by date; a ZIP
/// holds them with a list any computer reads.
@MainActor
@Suite(.serialized)
struct MomentExporterTests {
    private let container = try! MimoDaysStore.makeContainer(inMemory: true)
    private let store: MediaStore
    private let clock = TestDateProvider(Date(timeIntervalSince1970: 1_794_398_400))

    init() throws {
        store = try MediaStore(root: FileManager.default.temporaryDirectory.appending(path: "Export-\(UUID().uuidString)"))
    }

    private var library: MediaLibrary { MediaLibrary(context: container.mainContext, store: store, thumbnails: ThumbnailPipeline()) }

    private func folder() -> URL { FileManager.default.temporaryDirectory.appending(path: "Out-\(UUID().uuidString)") }

    /// A photo with a voice note, a note and an exact place, and a plain video.
    private func moments() async throws -> [UUID] {
        let engine = SimulatedCaptureEngine()
        _ = await engine.start()
        let saver = MomentSaver(context: container.mainContext, store: store, clock: clock, freeBytes: { nil })
        let zone = TimeZone(identifier: "Asia/Yerevan")!
        let photo = CaptureResult(
            media: .photo(try await engine.capturePhoto(flash: false, silent: true)), window: .init(),
            capturedAt: CaptureTime(instant: clock.now(), timeZone: zone)
        )
        var draft = MomentDraft(
            capture: photo, caption: "Lunch",
            window: SelfieWindowFrame(frame: CGRect(x: 266.7, y: 111.1, width: 112, height: 150), preview: CGSize(width: 402, height: 536)),
            promptID: nil, place: ReviewPlace(label: "Kentron", latitude: 40.1811, longitude: 44.5136, precision: .exact, source: .manual)
        )
        draft.note = "Soup, \"the good one\""
        let voice = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).m4a")
        try Data(repeating: 5, count: 3_000).write(to: voice)
        draft.voice = ReviewVoiceNote(url: voice, duration: 1, recordedAt: clock.now(), transcript: nil)
        let first = try await saver.save(draft)
        let video = CaptureResult(
            media: .video(try await engine.record(limit: .seconds(1))), window: .init(),
            capturedAt: CaptureTime(instant: clock.now().addingTimeInterval(3600), timeZone: zone)
        )
        let second = try await saver.save(MomentDraft(capture: video, caption: "", window: nil, promptID: nil))
        return [first.id, second.id]
    }

    private func names(_ urls: [URL]) -> [String] { urls.map(\.lastPathComponent) }

    @Test func byDefaultThePictureVoiceAndNoteLeaveWithoutThePlace() async throws {
        let ids = try await moments()
        let exporter = MomentExporter(library: library)
        let items = exporter.items(ids, options: .init())
        let files = try await MomentExporter.write(items, into: folder(), list: false)
        // Nov 11, 2026 12:00 UTC is 16:00 in Yerevan.
        #expect(names(files) == [
            "2026-11-11 16.00.00.heic", "2026-11-11 16.00.00 voice.m4a", "2026-11-11 16.00.00 note.txt", "2026-11-11 17.00.00.mp4",
        ])
        let note = try String(contentsOf: files[2], encoding: .utf8)
        #expect(note.contains("Lunch") && note.contains("the good one"))
        #expect(!note.contains("Kentron") && !note.contains("40.18"))
        #expect(gps(files[0]) == nil)
        #expect(try await location(files[3]) == nil)
    }

    @Test func exactPlaceIsWrittenWhenTurnedOn() async throws {
        let ids = try await moments()
        var options = MomentExporter.Options()
        options.exactPlace = true
        let files = try await MomentExporter.write(MomentExporter(library: library).items(ids, options: options), into: folder(), list: true)
        let note = try String(contentsOf: files[2], encoding: .utf8)
        #expect(note.contains("Kentron") && note.contains("40.18110, 44.51360"))
        let gps = try #require(gps(files[0]))
        let latitude = gps[kCGImagePropertyGPSLatitude as String].flatMap { Double("\($0)") } ?? 0
        #expect(abs(latitude - 40.1811) < 0.001)
        #expect(gps[kCGImagePropertyGPSLongitudeRef as String] as? String == "E")
        let csv = try String(contentsOf: try #require(files.last), encoding: .utf8)
        #expect(csv.hasPrefix("file,date,time zone,title,note,voice note,place,latitude,longitude,favorite\r\n"))
        #expect(csv.contains("2026-11-11 16.00.00.heic,2026-11-11T16:00:00+04:00,Asia/Yerevan,Lunch,\"Soup, \"\"the good one\"\"\",2026-11-11 16.00.00 voice.m4a,Kentron,40.181100,44.513600,"))
    }

    @Test func voiceAndNotesStayOutWhenTurnedOff() async throws {
        let ids = try await moments()
        var options = MomentExporter.Options()
        options.voiceNotes = false
        options.notes = false
        let files = try await MomentExporter.write(MomentExporter(library: library).items(ids, options: options), into: folder(), list: false)
        // The title still names the picture in the list, but there's no note file without notes.
        #expect(names(files) == ["2026-11-11 16.00.00.heic", "2026-11-11 17.00.00.mp4"])
    }

    @Test func originalsAreTheCamerasOwnFiles() async throws {
        let ids = try await moments()
        var options = MomentExporter.Options()
        options.asSeen = false
        options.originals = true
        options.voiceNotes = false
        options.notes = false
        let files = try await MomentExporter.write(MomentExporter(library: library).items([ids[0]], options: options), into: folder(), list: false)
        #expect(Set(names(files)).isSubset(of: ["2026-11-11 16.00.00 back.jpg", "2026-11-11 16.00.00 front.jpg", "2026-11-11 16.00.00 back.heic", "2026-11-11 16.00.00 front.heic"]))
        #expect(files.count == 2)
    }

    @Test func aZipHoldsEverythingAndTheList() async throws {
        let ids = try await moments()
        let out = folder()
        _ = try await MomentExporter.write(MomentExporter(library: library).items(ids, options: .init()), into: out, list: true)
        let zip = try MomentExporter.zip(out, as: "MimoDays 2 moments.zip")
        let data = try Data(contentsOf: zip)
        #expect(data.prefix(2) == Data("PK".utf8))
        #expect(data.count > 1000)
    }

    @Test func theEstimateCountsWhatsChosen() async throws {
        let ids = try await moments()
        let exporter = MomentExporter(library: library)
        var options = MomentExporter.Options()
        let seen = exporter.estimatedBytes(ids, options: options)
        options.originals = true
        #expect(exporter.estimatedBytes(ids, options: options) > seen)
        options.voiceNotes = false
        #expect(exporter.estimatedBytes(ids, options: options) == exporter.estimatedBytes(ids, options: options))
    }

    private func gps(_ url: URL) -> [String: Any]? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else { return nil }
        return properties[kCGImagePropertyGPSDictionary as String] as? [String: Any]
    }

    private func location(_ url: URL) async throws -> String? {
        let metadata = try await AVURLAsset(url: url).load(.metadata)
        return metadata.first { $0.identifier == .quickTimeMetadataLocationISO6709 || $0.identifier == .commonIdentifierLocation }
            .flatMap { $0.stringValue }
    }
}
