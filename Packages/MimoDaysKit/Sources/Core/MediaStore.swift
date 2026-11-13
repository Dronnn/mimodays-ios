import CryptoKit
import Foundation

/// A file saved in the media store. `relativePath` is what models keep.
public struct StoredFile: Equatable, Sendable {
    public var relativePath: String
    /// SHA-256, lowercase hex.
    public var checksum: String
    public var byteCount: Int64
}

public enum MediaStoreError: Error, Equatable, Sendable {
    case invalidPath(String)
    case missing(String)
}

/// On-disk home for all media. Files are never overwritten: each write gets a new name,
/// lands in place atomically and comes back with its checksum.
public struct MediaStore: Sendable {
    public enum Area: String, CaseIterable, Sendable {
        /// Captured photos and videos, voice notes, imported files, the person's own audio. Never purged.
        case originals
        /// Composed previews, thumbnails, rendered movies. Rebuildable but kept.
        case derived
        /// Purgeable at any time; excluded from device backups.
        case cache
    }

    public let root: URL

    public init(root: URL) throws {
        self.root = root.standardizedFileURL
        for area in Area.allCases {
            var url = self.root.appendingPathComponent(area.rawValue, isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            if area == .cache {
                var values = URLResourceValues()
                values.isExcludedFromBackup = true
                try url.setResourceValues(values)
            }
        }
    }

    /// Copies `source` into `area`. The copy is written to a temporary name first and moved into place,
    /// so a crash never leaves a half-written file under a real name.
    public func store(copyOf source: URL, in area: Area, fileExtension: String? = nil) throws -> StoredFile {
        let relativePath = newRelativePath(area, fileExtension ?? source.pathExtension)
        let destination = url(forUnchecked: relativePath)
        let staging = destination.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).partial")
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        do {
            try FileManager.default.copyItem(at: source, to: staging)
            try protect(staging)
            try FileManager.default.moveItem(at: staging, to: destination)
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw error
        }
        return try describe(relativePath)
    }

    /// Writes `data` into `area` atomically.
    public func store(_ data: Data, in area: Area, fileExtension: String) throws -> StoredFile {
        let relativePath = newRelativePath(area, fileExtension)
        let destination = url(forUnchecked: relativePath)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: destination, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        return try describe(relativePath)
    }

    /// Absolute URL for a stored path. Rejects paths that escape the store.
    public func url(for relativePath: String) throws -> URL {
        let url = url(forUnchecked: relativePath)
        guard url.path.hasPrefix(root.path + "/"), !relativePath.hasPrefix("/") else {
            throw MediaStoreError.invalidPath(relativePath)
        }
        return url
    }

    public func fileExists(_ relativePath: String) -> Bool {
        (try? url(for: relativePath)).map { FileManager.default.fileExists(atPath: $0.path) } ?? false
    }

    /// True when the file exists and still has `checksum`.
    public func verify(_ relativePath: String, checksum: String) throws -> Bool {
        let url = try url(for: relativePath)
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        return try Self.sha256(of: url) == checksum
    }

    public func remove(_ relativePath: String) throws {
        let url = try url(for: relativePath)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    /// Files in originals and derived that no record points to, e.g. after an interrupted save.
    /// Leftover staging files are always orphans.
    public func orphans(referenced: Set<String>) throws -> [String] {
        try [Area.originals, .derived].flatMap { try relativePaths(in: $0) }
            .filter { !referenced.contains($0) || ($0 as NSString).lastPathComponent.hasSuffix(".partial") }
            .sorted()
    }

    public func clearCache() throws {
        let cache = root.appendingPathComponent(Area.cache.rawValue, isDirectory: true)
        for item in try FileManager.default.contentsOfDirectory(at: cache, includingPropertiesForKeys: nil) {
            try FileManager.default.removeItem(at: item)
        }
    }

    /// Bytes used per area, for the Storage screen.
    public func usage() throws -> [Area: Int64] {
        var result: [Area: Int64] = [:]
        for area in Area.allCases {
            result[area] = try relativePaths(in: area).reduce(Int64(0)) { sum, path in
                let size = try url(forUnchecked: path).resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                return sum + Int64(size)
            }
        }
        return result
    }

    public static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Private

    /// `<area>/<first two hex digits>/<uuid>.<ext>` keeps folders small.
    private func newRelativePath(_ area: Area, _ fileExtension: String) -> String {
        let name = UUID().uuidString.lowercased()
        let file = fileExtension.isEmpty ? name : "\(name).\(fileExtension.lowercased())"
        return "\(area.rawValue)/\(name.prefix(2))/\(file)"
    }

    private func url(forUnchecked relativePath: String) -> URL {
        root.appendingPathComponent(relativePath).standardizedFileURL
    }

    private func describe(_ relativePath: String) throws -> StoredFile {
        let url = url(forUnchecked: relativePath)
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        return StoredFile(relativePath: relativePath, checksum: try Self.sha256(of: url), byteCount: Int64(size))
    }

    private func protect(_ url: URL) throws {
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path)
        #endif
    }

    private func relativePaths(in area: Area) throws -> [String] {
        let base = root.appendingPathComponent(area.rawValue, isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(at: base, includingPropertiesForKeys: [.isRegularFileKey]) else { return [] }
        var result: [String] = []
        for case let url as URL in enumerator where (try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
            result.append(String(url.standardizedFileURL.path.dropFirst(root.path.count + 1)))
        }
        return result
    }
}
