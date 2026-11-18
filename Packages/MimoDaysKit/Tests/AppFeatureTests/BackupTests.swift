@testable import AppFeature
@testable import Core
import Foundation
import Persistence
import SwiftData
import Testing
import TestSupport

/// 12.3, 12.5, 12.9: a backup restored on an empty iPhone gives back the same archive; damaged, foreign, newer
/// and repeated backups are handled without touching what's already here.
@MainActor
@Suite(.serialized)
struct BackupTests {
    private let clock = TestDateProvider(Date(timeIntervalSince1970: 1_794_398_400))
    private static var containers: [ModelContainer] = []

    /// A library on its own store, like a separate iPhone.
    private func library() throws -> MediaLibrary {
        let container = try TestStore.container()
        Self.containers.append(container)
        let store = try MediaStore(root: FileManager.default.temporaryDirectory.appending(path: "Backup-\(UUID().uuidString)"))
        return MediaLibrary(context: container.mainContext, store: store, thumbnails: ThumbnailPipeline())
    }

    private func temporary(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString)-\(name)")
    }

    /// Four moments (one with a voice note, a place, a note and a heart; one in Recently deleted), a collection
    /// and a rendered movie with music.
    private func fill(_ library: MediaLibrary) async throws -> [UUID] {
        let engine = SimulatedCaptureEngine()
        _ = await engine.start()
        let saver = MomentSaver(context: library.context, store: library.store, clock: clock, freeBytes: { nil })
        var moments: [Moment] = []
        for index in 0..<4 {
            let capture = CaptureResult(
                media: .photo(try await engine.capturePhoto(flash: .off, silent: true)), window: .init(),
                capturedAt: CaptureTime(instant: clock.now().addingTimeInterval(Double(index) * 86_400), timeZone: TimeZone(identifier: "Asia/Yerevan")!)
            )
            var draft = MomentDraft(
                capture: capture, caption: index == 0 ? "Lunch" : "",
                window: SelfieWindowFrame(frame: CGRect(x: 266.7, y: 111.1, width: 112, height: 150), preview: CGSize(width: 402, height: 536)),
                promptID: nil,
                place: index == 0 ? ReviewPlace(label: "Yerevan", latitude: 40.18, longitude: 44.51, precision: .exact, source: .manual) : nil
            )
            if index == 0 {
                draft.note = "A long note"
                let voice = temporary("voice.m4a")
                try Data(repeating: 7, count: 4_000).write(to: voice)
                draft.voice = ReviewVoiceNote(url: voice, duration: 2, recordedAt: clock.now(), transcript: "hello")
            }
            moments.append(try await saver.save(draft))
        }
        moments[0].isFavorite = true
        moments[3].deletedAt = clock.now()
        let collection = MomentCollection(title: "Trip", sortOrder: 0, createdAt: clock.now())
        library.context.insert(collection)
        for (position, moment) in moments.prefix(2).enumerated() {
            library.context.insert(CollectionMembership(collection: collection, moment: moment, position: position, addedAt: clock.now()))
        }
        let movies = MovieStore(context: library.context, store: library.store, now: { [clock] in clock.now() })
        let project = try movies.create(
            title: "October", source: MovieSourceRule(kind: .selection, momentIDs: moments.map(\.id)), length: .full,
            aspectRatio: .portrait9x16, fit: .fill, momentIDs: moments.prefix(3).map(\.id)
        )
        project.orderedClips[1].transition = .fade
        moments[1].captureFormat = .square
        project.orderedClips[2].cameraLayout = .sideBySide
        project.orderedClips[2].pipFrame = PiPLayout(centerX: 0.25, centerY: 0.75, scale: 0.35)
        project.orderedClips[2].atmosphere = MovieAtmosphere(lead: 2.5, leadsWith: .voiceComment)
        let card = MovieTextCard(project: project, position: 3, text: "The end", look: .plum, duration: 5)
        card.transition = .fade
        card.voiceNoteID = moments[0].voiceNotes.first?.id
        library.context.insert(card)
        let song = try library.store.store(Data(repeating: 3, count: 2_000), in: .originals, fileExtension: "m4a")
        let track = MovieAudioTrack(kind: .soundtrack, relativePath: song.relativePath, gain: 0.8)
        track.name = "Song"
        track.project = project
        library.context.insert(track)
        let render = try library.store.store(Data(repeating: 9, count: 5_000), in: .derived, fileExtension: "mp4")
        project.render = MovieRender(relativePath: render.relativePath, renderedAt: clock.now(), duration: 7.5, resolution: .p720, byteCount: 5_000)
        project.statusRaw = MovieStatus.rendered.rawValue
        try library.context.save()
        return moments.map(\.id)
    }

    private func backUp(_ library: MediaLibrary, renders: Bool = true) throws -> (URL, BackupDocument) {
        let service = BackupService(library: library, now: { [clock] in clock.now() })
        let plan = service.plan(includesRenders: renders)
        let url = temporary("backup.mimodays")
        let document = try BackupArchive.write(plan.document, files: plan.files, to: url)
        return (url, document)
    }

    private func restore(
        _ url: URL, into library: MediaLibrary, mode: BackupService.Mode = .addMissing, losing lost: Int = 0, damaging: Set<String> = []
    ) throws -> BackupService.Outcome {
        let service = BackupService(library: library, now: { [clock] in clock.now() })
        var check = try BackupArchive.check(url)
        check.damaged.formUnion(damaging)
        let wanted = service.files(for: check, mode: mode)
        let folder = temporary("unpacked")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var unpacked: [String: URL] = [:]
        try BackupArchive.extract(url, paths: wanted, into: folder) { path, file in unpacked[path] = file }
        // Files that couldn't be unpacked (no space).
        for path in unpacked.keys.sorted().prefix(lost) { unpacked[path] = nil }
        return try service.restore(check, mode: mode, unpacked: unpacked)
    }

    /// V7: replacing with a backup one of whose files can't come in keeps the library as it is.
    @Test func aReplacementMissingAFileKeepsTheLibrary() async throws {
        let phone = try library()
        _ = try await fill(phone)
        let (url, _) = try backUp(phone)
        let other = try library()
        let own = Set(try await fill(other))
        let files = try other.store.orphans(referenced: [])
        #expect(throws: (any Error).self) { try restore(url, into: other, mode: .replaceEverything, losing: 1) }
        #expect(Set(try other.context.fetch(FetchDescriptor<Moment>()).map(\.id)) == own)
        #expect(try other.store.orphans(referenced: []) == files)
    }

    /// The records as a backup would write them, with the store's file names left out.
    private func records(_ library: MediaLibrary) -> BackupDocument {
        var document = BackupService(library: library, now: { [clock] in clock.now() }).plan(includesRenders: true).document
        document.archiveID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
        for index in document.moments.indices {
            for media in document.moments[index].media.indices { document.moments[index].media[media].path = "" }
            for voice in document.moments[index].voiceNotes.indices { document.moments[index].voiceNotes[voice].path = "" }
        }
        for index in document.movies.indices {
            for track in document.movies[index].audioTracks.indices { document.movies[index].audioTracks[track].path = "" }
            document.movies[index].render?.relativePath = ""
        }
        return document
    }

    @Test func aRestoredBackupIsTheSameArchive() async throws {
        let phone = try library()
        _ = try await fill(phone)
        let (url, written) = try backUp(phone)
        #expect(written.moments.count == 3)
        #expect(written.files.count == written.moments.flatMap(\.paths).count + 2)

        let newPhone = try library()
        let outcome = try restore(url, into: newPhone)
        #expect(outcome == BackupService.Outcome(restored: 3, wanted: 3, damagedFiles: 0, alreadyHere: 0))
        #expect(records(newPhone) == records(phone))
        // Every file arrived whole.
        for moment in try newPhone.context.fetch(FetchDescriptor<Moment>()) {
            for media in moment.media { #expect(try newPhone.store.verify(media.relativePath, checksum: media.checksum)) }
            #expect(moment.voiceNotes.allSatisfy { newPhone.store.fileExists($0.relativePath) })
        }
        let project = try #require(try newPhone.context.fetch(FetchDescriptor<MovieProject>()).first)
        #expect(project.orderedClips.count == 3)
        #expect(project.orderedClips[2].cameraLayout == .sideBySide)
        #expect(project.textCards.map(\.text) == ["The end"])
        #expect(try newPhone.context.fetch(FetchDescriptor<Moment>()).filter { $0.captureFormat == .square }.count == 1)
        #expect(project.status == .rendered)
        #expect(newPhone.store.fileExists(try #require(project.render).relativePath))
        #expect(project.audioTracks.first.map { newPhone.store.fileExists($0.relativePath) } == true)
        let restored = try newPhone.context.fetch(FetchDescriptor<BackupManifest>())
        #expect(restored.count == 1 && restored[0].restoredAt != nil)
    }

    @Test func withoutRendersTheMovieComesBackAsADraft() async throws {
        let phone = try library()
        _ = try await fill(phone)
        let (url, written) = try backUp(phone, renders: false)
        #expect(written.movies[0].render == nil)
        let newPhone = try library()
        _ = try restore(url, into: newPhone)
        let project = try #require(try newPhone.context.fetch(FetchDescriptor<MovieProject>()).first)
        #expect(project.render == nil)
        #expect(project.status == .draft)
    }

    @Test func restoringTwiceAddsNothing() async throws {
        let phone = try library()
        _ = try await fill(phone)
        let (url, _) = try backUp(phone)
        let before = records(phone)
        let outcome = try restore(url, into: phone)
        #expect(outcome == BackupService.Outcome(restored: 0, wanted: 0, damagedFiles: 0, alreadyHere: 3))
        #expect(records(phone) == before)
        #expect(try phone.context.fetchCount(FetchDescriptor<MovieProject>()) == 1)
    }

    @Test func addingKeepsWhatsHereAndReplacingMatchesTheBackup() async throws {
        let phone = try library()
        _ = try await fill(phone)
        let (url, _) = try backUp(phone)
        let other = try library()
        let own = try await fill(other)

        let check = try BackupArchive.check(url)
        let summary = BackupService(library: other).summary(check)
        #expect(summary.moments == 3 && summary.alreadyHere == 0 && summary.new == 3 && summary.isClean)

        _ = try restore(url, into: other)
        #expect(try other.context.fetchCount(FetchDescriptor<Moment>()) == 7)

        let ownFiles = try other.context.fetch(FetchDescriptor<Moment>()).filter { own.contains($0.id) }.flatMap { $0.media.map(\.relativePath) }
        #expect(!ownFiles.isEmpty)
        _ = try restore(url, into: other, mode: .replaceEverything)
        let ids = Set(try other.context.fetch(FetchDescriptor<Moment>()).map(\.id))
        #expect(ids == Set(check.document.moments.map(\.id)))
        #expect(ids.isDisjoint(with: own))
        #expect(records(other) == records(phone))
        // The old library's files go once the new one is saved; the new one's are all there.
        #expect(ownFiles.allSatisfy { !FileManager.default.fileExists(atPath: (try? other.store.url(for: $0).path) ?? "") })
        let newFiles = try other.context.fetch(FetchDescriptor<Moment>()).flatMap { $0.media.map(\.relativePath) }
        #expect(newFiles.allSatisfy { FileManager.default.fileExists(atPath: (try? other.store.url(for: $0).path) ?? "/") })
    }

    @Test func aDamagedFileSkipsOnlyItsMoment() async throws {
        let phone = try library()
        _ = try await fill(phone)
        let (url, _) = try backUp(phone)
        // Damage a byte in the middle, where the media is.
        let handle = try FileHandle(forUpdating: url)
        let size = try handle.seekToEnd()
        try handle.seek(toOffset: size / 2)
        let byte = try #require(try handle.read(upToCount: 1)).first ?? 0
        try handle.seek(toOffset: size / 2)
        try handle.write(contentsOf: Data([byte ^ 0xFF]))
        try handle.close()

        let check = try BackupArchive.check(url)
        #expect(check.damaged.count == 1)
        let newPhone = try library()
        let outcome = try restore(url, into: newPhone)
        let hitsAMoment = check.document.moments.contains { !Set($0.paths).isDisjoint(with: check.damaged) }
        #expect(outcome.restored == (hitsAMoment ? 2 : 3))
        #expect(outcome.damagedFiles == (hitsAMoment ? 1 : 0))
    }

    @Test func anArchiveFromBeforeFormatsAndTextCardsStillReads() async throws {
        let phone = try library()
        _ = try await fill(phone)
        let document = BackupService(library: phone, now: { [clock] in clock.now() }).plan(includesRenders: true).document
        let newKeys: Set<String> = ["captureFormat", "textCards", "cameraLayout", "pipFrame", "atmosphere"]
        func strip(_ value: Any) -> Any {
            if let object = value as? [String: Any] { return object.filter { !newKeys.contains($0.key) }.mapValues(strip) }
            if let array = value as? [Any] { return array.map(strip) }
            return value
        }
        let json = try JSONSerialization.jsonObject(with: try BackupDocument.encoder().encode(document))
        let old = try BackupDocument.decoder().decode(BackupDocument.self, from: try JSONSerialization.data(withJSONObject: strip(json)))
        #expect(old.moments.count == document.moments.count)
        #expect(old.moments.allSatisfy { $0.captureFormat == nil && $0.moment(paths: [:]).captureFormat == .portrait })
        #expect(old.movies.first?.textCards == nil)
        #expect(old.movies.first?.clips.allSatisfy { $0.cameraLayout == nil && $0.pipFrame == nil && $0.atmosphere == nil } == true)
    }

    @Test func anythingElseIsNotABackup() throws {
        let url = temporary("photo.jpg")
        try Data(repeating: 1, count: 10_000).write(to: url)
        #expect(throws: BackupArchive.Failure.notABackup) { try BackupArchive.check(url) }
    }

    @Test func aCutOffBackupIsNotRestored() async throws {
        let phone = try library()
        _ = try await fill(phone)
        let (url, _) = try backUp(phone)
        let data = try Data(contentsOf: url)
        try data.prefix(data.count / 2).write(to: url)
        #expect(throws: BackupArchive.Failure.notABackup) { try BackupArchive.check(url) }
    }

    @Test func aNewerBackupAsksForAnUpdate() throws {
        var document = BackupDocument(createdAt: clock.now())
        document.formatVersion = BackupDocument.currentVersion + 1
        let url = temporary("newer.mimodays")
        _ = try BackupArchive.write(document, files: [], to: url)
        #expect(throws: BackupArchive.Failure.newerVersion(BackupDocument.currentVersion + 1)) { try BackupArchive.check(url) }
    }

    @Test func cancellingStopsTheBackup() async throws {
        let phone = try library()
        _ = try await fill(phone)
        let plan = BackupService(library: phone).plan(includesRenders: true)
        #expect(throws: BackupArchive.Failure.cancelled) {
            try BackupArchive.write(plan.document, files: plan.files, to: temporary("x.mimodays"), isCancelled: { true })
        }
    }

    @Test func statusCountsMomentsSinceTheLastBackup() async throws {
        let phone = try library()
        _ = try await fill(phone)
        let service = BackupService(library: phone, now: { [clock] in clock.now() })
        #expect(service.status().last == nil)
        #expect(service.status().newSince == 3)
        let (_, document) = try backUp(phone)
        service.record(document)
        #expect(service.status().last == clock.now())
        #expect(service.status().newSince == 0)
    }

    /// W2: replacing keeps a moment whose copy in the backup is damaged, in its collection again.
    @Test func replacingKeepsAMomentTheBackupCantBringBack() async throws {
        let phone = try library()
        let ids = try await fill(phone)
        let (url, document) = try backUp(phone)
        let hurt = try #require(document.moments.first { $0.id == ids[1] })
        let outcome = try restore(url, into: phone, mode: .replaceEverything, damaging: [hurt.paths[0]])
        let moments = try phone.context.fetch(FetchDescriptor<Moment>())
        #expect(Set(moments.map(\.id)) == Set(ids.prefix(3)))
        let kept = try #require(moments.first { $0.id == ids[1] })
        #expect(kept.media.allSatisfy { phone.store.fileExists($0.relativePath) })
        let trip = try #require(try phone.context.fetch(FetchDescriptor<MomentCollection>()).first)
        #expect(Set(trip.memberships.compactMap { $0.moment?.id }) == Set(ids.prefix(2)))
        #expect(outcome.skipped.isEmpty)
        // Nothing left behind: every file belongs to a record.
        #expect(OrphanFiles.remove(context: phone.context, store: phone.store) == 0)
    }

    /// W2: a file already gone from the iPhone (a lost voice note) leaves the backup without it, and the moment
    /// comes back with the rest.
    @Test func aMissingFileDoesntCostTheMoment() async throws {
        let phone = try library()
        let ids = try await fill(phone)
        let first = try #require(try phone.context.fetch(FetchDescriptor<Moment>()).first { $0.id == ids[0] })
        try phone.store.remove(try #require(first.voiceNotes.first).relativePath)
        let (url, document) = try backUp(phone)
        #expect(try #require(document.moments.first { $0.id == ids[0] }).voiceNotes.isEmpty)
        let newPhone = try library()
        let outcome = try restore(url, into: newPhone)
        #expect(outcome.restored == 3 && outcome.skipped.isEmpty)
    }

    /// W2: a moment recovered from Recently deleted after a backup isn't in it, though it's older.
    @Test func aMomentRecoveredAfterTheBackupIsNotInIt() async throws {
        let phone = try library()
        let ids = try await fill(phone)
        let service = BackupService(library: phone, now: { [clock] in clock.now() })
        let (_, document) = try backUp(phone)
        service.record(document)
        #expect(service.status().newSince == 0)
        let deleted = try #require(try phone.context.fetch(FetchDescriptor<Moment>()).first { $0.id == ids[3] })
        deleted.deletedAt = nil
        try phone.context.save()
        #expect(service.status().newSince == 1)
    }

    /// W2: adding from a backup whose moments are all here still brings back a movie deleted since.
    @Test func aDeletedMovieAloneCanBeAdded() async throws {
        let phone = try library()
        _ = try await fill(phone)
        let (url, _) = try backUp(phone)
        let service = BackupService(library: phone, now: { [clock] in clock.now() })
        #expect(!service.summary(try BackupArchive.check(url)).addsMore)
        for project in try phone.context.fetch(FetchDescriptor<MovieProject>()) { phone.context.delete(project) }
        try phone.context.save()
        let summary = service.summary(try BackupArchive.check(url))
        #expect(summary.new == 0 && summary.addsMore)
        _ = try restore(url, into: phone)
        #expect(try phone.context.fetchCount(FetchDescriptor<MovieProject>()) == 1)
    }

    /// V6: launch removes only files no record points to; a full library (Recently Deleted, voice note, music,
    /// render, thumbnails, composed pictures) keeps every file.
    @Test func launchRemovesOnlyFilesNoRecordKeeps() async throws {
        let library = try library()
        _ = try await fill(library)
        let before = try library.store.orphans(referenced: [])
        #expect(!before.isEmpty)
        #expect(OrphanFiles.remove(context: library.context, store: library.store) == 0)
        #expect(try library.store.orphans(referenced: []) == before)

        // A save that iOS ended after the files were written, and a half-written copy.
        let left = try library.store.store(Data(repeating: 1, count: 100), in: .originals, fileExtension: "heic")
        let partial = try library.store.url(for: "derived").appending(path: ".x.partial")
        try Data(repeating: 2, count: 10).write(to: partial)
        #expect(OrphanFiles.remove(context: library.context, store: library.store) == 2)
        #expect(!FileManager.default.fileExists(atPath: try library.store.url(for: left.relativePath).path))
        #expect(try library.store.orphans(referenced: []) == before)
    }
}
