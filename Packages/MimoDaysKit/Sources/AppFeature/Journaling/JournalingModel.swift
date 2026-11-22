import Core
import Foundation
import Observation
import UIKit

/// P8.12: what MimoDays takes from the suggestion picked in Apple's Journaling Suggestions picker - its photos and its
/// writing prompts. Workouts, music, contacts, places and the rest are left alone in this release.
struct JournalingPick: Equatable, Sendable {
    struct Photo: Equatable, Sendable {
        var url: URL
        /// When the photo was taken, if the suggestion says.
        var date: Date?
    }

    var title: String
    /// When the suggestion happened.
    var date: Date?
    var photos: [Photo] = []
    var prompts: [String] = []
}

/// DD04 and its states: opening the suggestion, choosing a photo or the prompt, nothing to add, couldn't open.
@MainActor
@Observable
final class JournalingModel: Identifiable {
    enum Phase: Equatable {
        case loading
        case ready
        /// Nothing MimoDays can use: no photo, no prompt.
        case unsupported
        /// Its photos couldn't be read.
        case failed
    }

    /// With both photos and a prompt: "Use a photo" or "Write from this prompt".
    enum Use: Hashable {
        case photo
        case prompt
    }

    /// What Continue leads to, after the sheet has closed.
    enum Next: Equatable {
        case importPhoto(JournalingPick.Photo)
        case write(prompt: String?)
        case chooseAgain
    }

    let id = UUID()
    private(set) var phase = Phase.loading
    private(set) var pick: JournalingPick?
    var use = Use.photo
    /// The photo chosen; several must be chosen from, one is chosen already.
    var chosen: Int?
    private(set) var thumbnails: [Int: UIImage] = [:]
    private let load: @MainActor () async throws -> JournalingPick

    init(load: @escaping @MainActor () async throws -> JournalingPick) {
        self.load = load
    }

    /// Opens the suggestion; Try again runs it once more.
    func start() async {
        phase = .loading
        pick = nil
        chosen = nil
        thumbnails = [:]
        guard let loaded = try? await load() else {
            phase = .failed
            return
        }
        // A photo is usable once it opens as a picture.
        var usable: [JournalingPick.Photo] = []
        var thumbnails: [Int: UIImage] = [:]
        for photo in loaded.photos {
            guard let image = await ReviewModel.still(photo.url, maxPixelSize: 360, at: 0) else { continue }
            thumbnails[usable.count] = image
            usable.append(photo)
        }
        var pick = loaded
        pick.photos = usable
        pick.prompts = loaded.prompts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        self.thumbnails = thumbnails
        self.pick = pick
        chosen = usable.count == 1 ? 0 : nil
        use = usable.isEmpty ? .prompt : .photo
        if usable.isEmpty, pick.prompts.isEmpty {
            phase = loaded.photos.isEmpty ? .unsupported : .failed
        } else {
            phase = .ready
        }
    }

    var offersBoth: Bool { !(pick?.photos.isEmpty ?? true) && prompt != nil }
    var prompt: String? { pick?.prompts.first }

    var canContinue: Bool {
        switch use {
        case .photo: chosen != nil
        case .prompt: prompt != nil
        }
    }

    /// Continue: the chosen photo to the import review, or the prompt to Write a moment.
    var next: Next? {
        guard phase == .ready, canContinue, let pick else { return nil }
        switch use {
        case .photo: return chosen.map { .importPhoto(pick.photos[$0]) }
        case .prompt: return .write(prompt: prompt)
        }
    }
}

/// The chosen photo handed to the import review (P8.5): copied out of the picker's file, dated by the suggestion when
/// the file has no date.
struct JournalingPhotoItem: PhotoPickerItemLoading {
    let photo: JournalingPick.Photo

    func loadFile() async throws -> PickedFile? {
        var file = PickedFile(url: try PickedFile.copy(photo.url), isVideo: false)
        file.date = photo.date
        return file
    }
}

/// Where the menu offers it: Apple's picker runs on iPhone, and on iPad from iPadOS 26. UI tests on the simulator get
/// their stand-in picker instead.
enum JournalingAvailability {
    @MainActor
    static func isOffered(fixture: LaunchConfiguration.JournalingFixture?) -> Bool {
        if fixture != nil { return true }
        #if canImport(JournalingSuggestions)
        if UIDevice.current.userInterfaceIdiom == .phone { return true }
        if #available(iOS 26, *) { return UIDevice.current.userInterfaceIdiom == .pad }
        return false
        #else
        return false
        #endif
    }
}

extension LaunchConfiguration.JournalingFixture {
    /// The suggestion it stands for; its photos are drawn into temporary files.
    func pick() throws -> JournalingPick {
        func photos(_ count: Int) throws -> [JournalingPick.Photo] {
            let colors = [UIColor(red: 0.91, green: 0.65, blue: 0.49, alpha: 1), UIColor(red: 0.56, green: 0.73, blue: 0.66, alpha: 1), UIColor(red: 0.78, green: 0.63, blue: 0.79, alpha: 1)]
            return try (0..<count).map { index in
                let image = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 450)).image { context in
                    colors[index % colors.count].setFill()
                    context.fill(CGRect(x: 0, y: 0, width: 600, height: 450))
                }
                let url = FileManager.default.temporaryDirectory.appending(path: "Journaling-\(UUID().uuidString).jpg")
                try image.jpegData(compressionQuality: 0.8)?.write(to: url)
                return JournalingPick.Photo(url: url, date: index == 0 ? Date(timeIntervalSince1970: 1_795_000_000) : nil)
            }
        }
        let date = Date(timeIntervalSince1970: 1_795_250_000)
        switch self {
        case .photos: return JournalingPick(title: "Republic Square", date: date, photos: try photos(3))
        case .prompt: return JournalingPick(title: "Reflection", date: date, prompts: ["What made you smile today?"])
        case .both: return JournalingPick(title: "Republic Square", date: date, photos: try photos(2), prompts: ["What made you smile today?"])
        case .nothing: return JournalingPick(title: "Morning run", date: date)
        }
    }
}
