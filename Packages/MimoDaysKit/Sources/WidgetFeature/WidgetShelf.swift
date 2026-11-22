import Foundation
import os
import UIKit

/// P8.2: the widgets' copy in the App Group, kept apart from the archive. The app writes it whole and empties it at
/// once on opt-out, App Lock or Delete all data; the widgets only read it, and keep which random memory shows.
public struct WidgetShelf: Sendable {
    public static let appGroup = "group.com.mrmaier.MimoDays"

    public let directory: URL
    private static let logger = Logger(subsystem: "MimoDays", category: "Widgets")

    public init(directory: URL) {
        self.directory = directory
    }

    /// The App Group's shelf; nil where the group isn't there (tests, a build without the entitlement).
    public static var shared: WidgetShelf? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
            .map { WidgetShelf(directory: $0.appending(path: "Widgets", directoryHint: .isDirectory)) }
    }

    private var payloadURL: URL { directory.appending(path: "payload.json") }
    private var pickURL: URL { directory.appending(path: "pick") }

    public func read() -> WidgetPayload? {
        guard let data = try? Data(contentsOf: payloadURL) else { return nil }
        return try? JSONDecoder().decode(WidgetPayload.self, from: data)
    }

    /// Pictures first, then the payload naming them; pictures it no longer names go.
    public func write(_ payload: WidgetPayload, images: [String: Data]) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (name, data) in images where payload.images.contains(name) {
            try data.write(to: directory.appending(path: name), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
        let data = try JSONEncoder().encode(payload)
        try data.write(to: payloadURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        removeImages(except: payload.images)
    }

    /// The names of the pictures already on the shelf, so unchanged ones aren't made again.
    public var imageNames: Set<String> {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))) ?? []
        return Set(names.filter { $0.hasSuffix(".jpg") })
    }

    public func image(_ name: String) -> UIImage? {
        UIImage(contentsOfFile: directory.appending(path: name).path(percentEncoded: false))
    }

    /// Everything goes; the widgets show their plain tile until the app writes again.
    public func purge() {
        do {
            if FileManager.default.fileExists(atPath: directory.path(percentEncoded: false)) {
                try FileManager.default.removeItem(at: directory)
            }
        } catch {
            Self.logger.error("Emptying the widgets' shelf failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// The random memory on show, set by Another.
    public var pick: UUID? {
        get { (try? String(contentsOf: pickURL, encoding: .utf8)).flatMap(UUID.init(uuidString:)) }
        nonmutating set {
            guard let newValue else {
                try? FileManager.default.removeItem(at: pickURL)
                return
            }
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? newValue.uuidString.write(to: pickURL, atomically: true, encoding: .utf8)
        }
    }

    private func removeImages(except kept: Set<String>) {
        for name in imageNames.subtracting(kept) {
            try? FileManager.default.removeItem(at: directory.appending(path: name))
        }
    }
}
