@testable import AppFeature
import Core
import Foundation
import Testing

/// A store that can't be opened: the launch doesn't crash, and setting aside keeps every file (Andrew, 2026-11-20).
@MainActor
struct StoreRecoveryTests {
    @Test func aStoreThatFailsToOpenThrowsInsteadOfCrashing() {
        #expect(throws: (any Error).self) {
            try AppDependencies(configuration: LaunchConfiguration(isUITesting: true, breaksStore: true))
        }
    }

    @Test func settingAsideMovesTheStoreAndTheMediaTogetherAndDeletesNothing() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "SetAside-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let support = root.appending(path: "Support", directoryHint: .isDirectory)
        let media = support.appending(path: "Media", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: media.appending(path: "originals"), withIntermediateDirectories: true)
        let store = support.appending(path: "default.store")
        for name in ["default.store", "default.store-shm", "default.store-wal", "other.plist"] {
            try Data(name.utf8).write(to: support.appending(path: name))
        }
        try Data("photo".utf8).write(to: media.appending(path: "originals/a.heic"))

        try AppDependencies.setAside(store: store, media: media, into: root, now: Date(timeIntervalSince1970: 1_794_000_000))

        let aside = try #require(try FileManager.default.contentsOfDirectory(at: root.appending(path: "Set aside"), includingPropertiesForKeys: nil).first)
        let moved = Set(try FileManager.default.contentsOfDirectory(atPath: aside.path(percentEncoded: false)))
        #expect(moved == ["default.store", "default.store-shm", "default.store-wal", "Media"])
        #expect(FileManager.default.fileExists(atPath: aside.appending(path: "Media/originals/a.heic").path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: support.appending(path: "other.plist").path(percentEncoded: false)))
        #expect(!FileManager.default.fileExists(atPath: store.path(percentEncoded: false)))
        #expect(!FileManager.default.fileExists(atPath: media.path(percentEncoded: false)))
    }
}
