import Core
import Foundation
import Testing
import TestSupport

struct MediaStoreTests {
    private let directory: TemporaryDirectory
    private let store: MediaStore

    init() throws {
        directory = try TemporaryDirectory()
        store = try MediaStore(root: directory.url.appendingPathComponent("Media"))
    }

    @Test func storingCopiesWithChecksumAndLayout() throws {
        let stored = try store.store(copyOf: Fixture.backPhoto.url, in: .originals)
        #expect(stored.relativePath.hasPrefix("originals/"))
        #expect(stored.relativePath.hasSuffix(".jpg"))
        #expect(stored.relativePath.split(separator: "/").count == 3)
        #expect(stored.checksum == (try MediaStore.sha256(of: Fixture.backPhoto.url)))
        #expect(stored.byteCount == Int64(try Data(contentsOf: Fixture.backPhoto.url).count))
        #expect(FileManager.default.fileExists(atPath: Fixture.backPhoto.url.path), "source is left alone")
    }

    @Test func everyStoreGetsANewName() throws {
        let first = try store.store(copyOf: Fixture.clip.url, in: .originals)
        let second = try store.store(copyOf: Fixture.clip.url, in: .originals)
        #expect(first.relativePath != second.relativePath)
        #expect(first.checksum == second.checksum)
    }

    @Test func verifyDetectsChangedAndMissingFiles() throws {
        let stored = try store.store(Data("hello".utf8), in: .derived, fileExtension: "txt")
        #expect(try store.verify(stored.relativePath, checksum: stored.checksum))

        try Data("tampered".utf8).write(to: try store.url(for: stored.relativePath))
        #expect(try !store.verify(stored.relativePath, checksum: stored.checksum))

        try store.remove(stored.relativePath)
        #expect(try !store.verify(stored.relativePath, checksum: stored.checksum))
    }

    @Test func failedCopyLeavesNothingBehind() throws {
        let missing = directory.url.appendingPathComponent("nope.jpg")
        #expect(throws: (any Error).self) { try store.store(copyOf: missing, in: .originals) }
        #expect(try store.orphans(referenced: []).isEmpty)
    }

    @Test func orphansAreFilesNoRecordPointsTo() throws {
        let kept = try store.store(copyOf: Fixture.frontPhoto.url, in: .originals)
        let lost = try store.store(copyOf: Fixture.voiceNote.url, in: .originals)
        let preview = try store.store(Data([1, 2, 3]), in: .derived, fileExtension: "heic")
        _ = try store.store(Data([4]), in: .cache, fileExtension: "jpg")

        let orphans = try store.orphans(referenced: [kept.relativePath, preview.relativePath])
        #expect(orphans == [lost.relativePath])
    }

    @Test func interruptedWriteLeftoverIsAnOrphan() throws {
        let folder = store.root.appendingPathComponent("originals/ab", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data([0]).write(to: folder.appendingPathComponent(".interrupted.partial"))
        #expect(try store.orphans(referenced: ["originals/ab/.interrupted.partial"]) == ["originals/ab/.interrupted.partial"])
    }

    @Test func pathsCannotEscapeTheStore() {
        #expect(throws: MediaStoreError.invalidPath("../outside.jpg")) { try store.url(for: "../outside.jpg") }
        #expect(throws: MediaStoreError.invalidPath("/etc/hosts")) { try store.url(for: "/etc/hosts") }
    }

    @Test func cacheIsPurgeableAndNotBackedUp() throws {
        let cached = try store.store(Data([9]), in: .cache, fileExtension: "jpg")
        let original = try store.store(copyOf: Fixture.backPhoto.url, in: .originals)
        let cacheFolder = store.root.appendingPathComponent("cache", isDirectory: true)
        #expect(try cacheFolder.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)

        try store.clearCache()
        #expect(!store.fileExists(cached.relativePath))
        #expect(store.fileExists(original.relativePath))
    }

    @Test func usageAddsUpPerArea() throws {
        let original = try store.store(copyOf: Fixture.backPhoto.url, in: .originals)
        let usage = try store.usage()
        #expect(usage[.originals] == original.byteCount)
        #expect(usage[.cache] == 0)
    }
}
