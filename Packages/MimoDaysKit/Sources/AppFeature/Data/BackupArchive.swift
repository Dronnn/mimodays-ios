@preconcurrency import AppleArchive
import CryptoKit
import Foundation
import System

/// Reads and writes `.mimodays` files: an Apple Archive (readable on a Mac with `aa extract`) holding the
/// media under `media/` and `manifest.json` last, written after every file has been hashed on its way in.
enum BackupArchive {
    enum Failure: Error, Equatable {
        /// Not an archive, or no MimoDays manifest in it.
        case notABackup
        /// Made by a newer MimoDays; update first.
        case newerVersion(Int)
        case cancelled
        case unreadable
    }

    /// What reading the whole archive found: its manifest, and the files that are missing or don't match it.
    struct Check: Equatable {
        var document: BackupDocument
        var damaged: Set<String>
    }

    private static let chunk = 1 << 20
    private static var path: ArchiveHeader.FieldKey { ArchiveHeader.FieldKey("PAT") }
    private static var type: ArchiveHeader.FieldKey { ArchiveHeader.FieldKey("TYP") }
    private static var data: ArchiveHeader.FieldKey { ArchiveHeader.FieldKey("DAT") }

    /// Writes the files (store path -> file) and then the manifest with their checksums. `progress` gets the
    /// share of bytes written; `isCancelled` is asked between chunks.
    static func write(
        _ document: BackupDocument, files: [(path: String, url: URL)], to destination: URL,
        progress: (Double) -> Void = { _ in }, isCancelled: () -> Bool = { false }
    ) throws -> BackupDocument {
        guard let file = ArchiveByteStream.fileStream(
            path: FilePath(destination.path), mode: .writeOnly, options: [.create, .truncate], permissions: FilePermissions(rawValue: 0o644)
        ) else { throw Failure.unreadable }
        defer { try? file.close() }
        guard let encoder = ArchiveStream.encodeStream(writingTo: file) else { throw Failure.unreadable }
        defer { try? encoder.close() }

        var document = document
        let total = max(files.reduce(Int64(0)) { $0 + Self.size($1.url) }, 1)
        var written: Int64 = 0
        var folders: Set<String> = []
        for (relativePath, url) in files {
            let entry = "\(BackupDocument.mediaFolder)/\(relativePath)"
            for folder in Self.folders(of: entry) where folders.insert(folder).inserted {
                try encoder.writeHeader(Self.header(folder, type: .directory, size: nil))
            }
            let size = Self.size(url)
            try encoder.writeHeader(Self.header(entry, type: .regularFile, size: size))
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            var hasher = SHA256()
            var left = size
            while left > 0 {
                if isCancelled() { throw Failure.cancelled }
                let bytes = try handle.read(upToCount: min(Self.chunk, Int(left))) ?? Data()
                guard !bytes.isEmpty else { throw Failure.unreadable }
                hasher.update(data: bytes)
                try bytes.withUnsafeBytes { try encoder.writeBlob(key: Self.data, from: $0) }
                left -= Int64(bytes.count)
                written += Int64(bytes.count)
                progress(Double(written) / Double(total))
            }
            document.files[relativePath] = .init(sha256: Self.hex(hasher.finalize()), bytes: size)
        }
        let manifest = try BackupDocument.encoder().encode(document)
        try encoder.writeHeader(Self.header(BackupDocument.manifestPath, type: .regularFile, size: Int64(manifest.count)))
        try manifest.withUnsafeBytes { try encoder.writeBlob(key: Self.data, from: $0) }
        return document
    }

    /// Reads every entry, hashing it, then holds the hashes against the manifest (E07's "checked").
    static func check(_ url: URL, progress: (Double) -> Void = { _ in }, isCancelled: () -> Bool = { false }) throws -> Check {
        var hashes: [String: String] = [:]
        var manifest: Data?
        let total = max(Self.size(url), 1)
        var read: Int64 = 0
        try entries(of: url) { entry, size, next in
            var hasher = SHA256()
            var bytes = Data()
            while let piece = try next() {
                if isCancelled() { throw Failure.cancelled }
                if entry == BackupDocument.manifestPath { bytes.append(piece) } else { hasher.update(data: piece) }
                read += Int64(piece.count)
                progress(min(Double(read) / Double(total), 1))
            }
            if entry == BackupDocument.manifestPath {
                manifest = bytes
            } else if entry.hasPrefix(BackupDocument.mediaFolder + "/") {
                hashes[String(entry.dropFirst(BackupDocument.mediaFolder.count + 1))] = Self.hex(hasher.finalize())
            }
        }
        let document = try Self.document(manifest)
        // A file a record needs that isn't in the archive (gone from the iPhone it was made on) counts as damaged too.
        let referenced = Set(document.moments.flatMap(\.paths) + document.movies.flatMap(\.paths))
        let damaged = Set(document.files.compactMap { path, entry in hashes[path] == entry.sha256 ? nil : path })
            .union(referenced.subtracting(document.files.keys))
        return Check(document: document, damaged: damaged)
    }

    /// Writes the wanted files to `folder` (named by their store path) and hands each one over as it lands.
    /// One whose bytes no longer match `checksums` (the file changed since it was checked) isn't handed over.
    static func extract(
        _ url: URL, paths wanted: Set<String>, checksums: [String: String] = [:], into folder: URL,
        progress: (Double) -> Void = { _ in }, isCancelled: () -> Bool = { false }, received: (String, URL) throws -> Void
    ) throws {
        guard !wanted.isEmpty else { return }
        let total = max(Self.size(url), 1)
        var read: Int64 = 0
        try entries(of: url) { entry, _, next in
            let relativePath = entry.hasPrefix(BackupDocument.mediaFolder + "/") ? String(entry.dropFirst(BackupDocument.mediaFolder.count + 1)) : nil
            guard let relativePath, wanted.contains(relativePath) else {
                while let piece = try next() {
                    if isCancelled() { throw Failure.cancelled }
                    read += Int64(piece.count)
                    progress(min(Double(read) / Double(total), 1))
                }
                return
            }
            let target = folder.appendingPathComponent(UUID().uuidString).appendingPathExtension((relativePath as NSString).pathExtension)
            FileManager.default.createFile(atPath: target.path, contents: nil)
            let handle = try FileHandle(forWritingTo: target)
            var hasher = SHA256()
            do {
                while let piece = try next() {
                    if isCancelled() { throw Failure.cancelled }
                    try handle.write(contentsOf: piece)
                    hasher.update(data: piece)
                    read += Int64(piece.count)
                    progress(min(Double(read) / Double(total), 1))
                }
                try handle.close()
            } catch {
                try? handle.close()
                try? FileManager.default.removeItem(at: target)
                throw error
            }
            if let expected = checksums[relativePath], Self.hex(hasher.finalize()) != expected {
                try? FileManager.default.removeItem(at: target)
                return
            }
            try received(relativePath, target)
        }
    }

    // MARK: Private

    /// Calls `entry` for every regular file with its path, its size and a reader of its next chunk.
    private static func entries(of url: URL, entry: (String, Int64, () throws -> Data?) throws -> Void) throws {
        guard let file = ArchiveByteStream.fileStream(path: FilePath(url.path), mode: .readOnly, options: [], permissions: FilePermissions(rawValue: 0o644))
        else { throw Failure.unreadable }
        defer { try? file.close() }
        guard let decoder = ArchiveStream.decodeStream(readingFrom: file) else { throw Failure.notABackup }
        defer { try? decoder.close() }
        do {
            while let header = try decoder.readHeader() {
                guard case let .string(_, path)? = header.field(forKey: Self.path),
                      case let .uint(_, type)? = header.field(forKey: Self.type),
                      type == UInt64(ArchiveHeader.EntryType.regularFile.rawValue) else { continue }
                guard case let .blob(_, size, _)? = header.field(forKey: Self.data) else {
                    try entry(path, 0) { nil }
                    continue
                }
                var left = Int64(size)
                var buffer = [UInt8](repeating: 0, count: Self.chunk)
                try entry(path, Int64(size)) {
                    guard left > 0 else { return nil }
                    let count = Int(min(Int64(Self.chunk), left))
                    try buffer.withUnsafeMutableBytes { raw in
                        try decoder.readBlob(key: Self.data, into: UnsafeMutableRawBufferPointer(rebasing: raw[0..<count]))
                    }
                    left -= Int64(count)
                    return Data(buffer[0..<count])
                }
                // An entry the reader stopped early: skip the rest of its data.
                while left > 0 {
                    let count = Int(min(Int64(Self.chunk), left))
                    try buffer.withUnsafeMutableBytes { raw in
                        try decoder.readBlob(key: Self.data, into: UnsafeMutableRawBufferPointer(rebasing: raw[0..<count]))
                    }
                    left -= Int64(count)
                }
            }
        } catch let failure as Failure {
            throw failure
        } catch {
            throw Failure.notABackup
        }
    }

    private static func document(_ manifest: Data?) throws -> BackupDocument {
        guard let manifest else { throw Failure.notABackup }
        struct Version: Decodable {
            var format: String
            var formatVersion: Int
        }
        guard let version = try? BackupDocument.decoder().decode(Version.self, from: manifest), version.format == BackupDocument.format else {
            throw Failure.notABackup
        }
        guard version.formatVersion <= BackupDocument.currentVersion else { throw Failure.newerVersion(version.formatVersion) }
        guard let document = try? BackupDocument.decoder().decode(BackupDocument.self, from: manifest) else { throw Failure.notABackup }
        return document
    }

    private static func header(_ path: String, type: ArchiveHeader.EntryType, size: Int64?) -> ArchiveHeader {
        let header = ArchiveHeader()
        header.append(.uint(key: Self.type, value: UInt64(type.rawValue)))
        header.append(.string(key: Self.path, value: path))
        if let size { header.append(.blob(key: Self.data, size: UInt64(size))) }
        return header
    }

    /// "media", "media/originals", "media/originals/ab" for "media/originals/ab/x.heic".
    private static func folders(of path: String) -> [String] {
        let parts = path.split(separator: "/").dropLast()
        return parts.indices.map { parts[...$0].joined(separator: "/") }
    }

    static func size(_ url: URL) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }

    private static func hex(_ digest: SHA256.Digest) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }
}
