import Foundation
import SwiftData

/// Small media files bundled for tests (generated, no real people or places).
public enum Fixture: String, CaseIterable, Sendable {
    /// 900x1200 JPEG, rear camera.
    case backPhoto = "back.jpg"
    /// 360x480 JPEG, front camera.
    case frontPhoto = "front.jpg"
    /// 2 s, 360x480 H.264 video, no audio.
    case clip = "clip.mov"
    /// 2 s AAC mono voice note.
    case voiceNote = "voice.m4a"

    public var url: URL {
        guard let url = Bundle.module.url(forResource: rawValue, withExtension: nil, subdirectory: "Fixtures") else {
            preconditionFailure("Missing fixture \(rawValue)")
        }
        return url
    }

    /// Copies the fixture into `directory`, the way captured media lands in the file store.
    public func copy(to directory: URL) throws -> URL {
        let destination = directory.appendingPathComponent(rawValue)
        try FileManager.default.copyItem(at: url, to: destination)
        return destination
    }
}

/// A unique directory under the system temp folder, removed when released.
public final class TemporaryDirectory: Sendable {
    public let url: URL

    public init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("MimoDaysTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}

/// SwiftData container that lives only in memory, for integration tests.
public func makeInMemoryContainer(for types: [any PersistentModel.Type]) throws -> ModelContainer {
    try ModelContainer(for: Schema(types), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
}
