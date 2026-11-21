import Core
import CoreTransferable
import Foundation
import Persistence
import Photos
import UniformTypeIdentifiers

extension Moment {
    /// P8.6: the paired motion of an imported Live Photo.
    var livePhotoMotion: MomentMedia? { media.first { $0.role == .livePhotoMotion } }

    /// How long a movie can play it: a video's length, a Live Photo's motion; nil for a still.
    var movieVideoDuration: Double? {
        if mediaType == .video { return media.compactMap(\.duration).max() ?? MovieSelection.photoSeconds }
        return livePhotoMotion.map { $0.duration ?? MovieSelection.photoSeconds }
    }
}

extension UTType {
    /// What Photos' picker hands over for a Live Photo: a folder with the still and its paired movie.
    static let livePhotoBundle = UTType("com.apple.live-photo-bundle") ?? UTType(importedAs: "com.apple.live-photo-bundle", conformingTo: .package)
}

/// P8.6: a Live Photo picked in Photos, as two files in tmp (still and motion), without Photos access.
enum LivePhotoFiles {
    enum Failure: Error { case incomplete }

    /// The still and the movie out of a picked bundle, copied to tmp; both must be there.
    static func split(bundle: URL) throws -> PickedFile {
        let files = (try? FileManager.default.contentsOfDirectory(at: bundle, includingPropertiesForKeys: nil)) ?? []
        func first(_ type: UTType) -> URL? {
            files.sorted { $0.lastPathComponent < $1.lastPathComponent }
                .first { UTType(filenameExtension: $0.pathExtension)?.conforms(to: type) == true }
        }
        guard let still = first(.image), let motion = first(.movie) else { throw Failure.incomplete }
        let stillCopy = try PickedFile.copy(still)
        do {
            return PickedFile(url: stillCopy, isVideo: false, motionURL: try PickedFile.copy(motion), isLivePhoto: true)
        } catch {
            try? FileManager.default.removeItem(at: stillCopy)
            throw error
        }
    }

    /// The same from a `PHLivePhoto` the picker loaded: its photo and paired video resources, written to tmp.
    static func write(_ livePhoto: PHLivePhoto) async throws -> PickedFile {
        let resources = PHAssetResource.assetResources(for: livePhoto)
        guard let still = resources.first(where: { $0.type == .photo }), let motion = resources.first(where: { $0.type == .pairedVideo })
        else { throw Failure.incomplete }
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true
        var written: [URL] = []
        do {
            for resource in [still, motion] {
                let url = try PickedFile.target(extension: (resource.originalFilename as NSString).pathExtension)
                try await PHAssetResourceManager.default().writeData(for: resource, toFile: url, options: options)
                written.append(url)
            }
        } catch {
            written.forEach { try? FileManager.default.removeItem(at: $0) }
            throw error
        }
        return PickedFile(url: written[0], isVideo: false, motionURL: written[1], isLivePhoto: true)
    }
}

/// The bundle the picker hands over for a Live Photo.
struct LivePhotoBundleFile: Transferable {
    let file: PickedFile

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .livePhotoBundle) { received in LivePhotoBundleFile(file: try LivePhotoFiles.split(bundle: received.file)) }
    }
}
