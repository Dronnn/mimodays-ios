import Core
import Foundation
import Observation
import os
import Persistence
import SwiftData
import UIKit

/// M07: what can change about a saved moment - its words, voice note, place and favourite. The picture and its time
/// stay as they were. Nothing is written until Save.
@MainActor
@Observable
final class EditMomentModel: Identifiable, PlaceChoosing {
    /// The voice note as it will be saved: the one already kept, or a new recording waiting in a temporary file.
    enum Voice: Equatable {
        case saved(duration: Double)
        case recorded(ReviewVoiceNote)

        var duration: Double {
            switch self {
            case let .saved(duration): duration
            case let .recorded(voice): voice.duration
            }
        }
    }

    let id: UUID
    let library: MediaLibrary
    let captured: CaptureTime
    let mediaType: MediaType
    private(set) var thumbnail: UIImage?
    var caption: String
    var note: String
    var isFavorite: Bool
    private(set) var place: ReviewPlace?
    private(set) var placeWasChosen = false
    private(set) var voice: Voice?
    /// The collections it will be in.
    var collectionIDs: Set<UUID>
    private(set) var isSaving = false

    // Choosing a place later: no current city or nearby places, only search (near where it was), recents and No place.
    let currentPlace: ReviewPlace? = nil
    let isLocating = false
    let nearby: [PlaceSuggestion] = []

    private let original: (caption: String, note: String, isFavorite: Bool, place: ReviewPlace?, voice: Voice?)
    private let originalCollections: Set<UUID>
    private let thumbnailPath: String?
    private let voiceServices: VoiceServices
    private let places: PlaceServices
    private var transcription: Task<Void, Never>?
    private let logger = Logger(subsystem: "MimoDays", category: "EditMoment")

    /// Nil when the moment is gone.
    init?(id: UUID, library: MediaLibrary, voice: VoiceServices, places: PlaceServices) {
        var descriptor = FetchDescriptor<Moment>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let moment = try? library.context.fetch(descriptor).first, moment.deletedAt == nil else { return nil }
        self.id = id
        self.library = library
        voiceServices = voice
        self.places = places
        captured = MomentSummary(moment).captured
        mediaType = moment.mediaType
        thumbnailPath = moment.media.first { $0.role == .thumbnail }?.relativePath
        let place = moment.location.map {
            ReviewPlace(label: $0.placeLabel, latitude: $0.latitude, longitude: $0.longitude, precision: $0.precision, source: $0.source)
        }
        let saved = moment.voiceNotes.first.map { Voice.saved(duration: $0.duration) }
        original = (moment.title ?? "", moment.note ?? "", moment.isFavorite, place, saved)
        caption = original.caption
        note = original.note
        isFavorite = original.isFavorite
        self.place = place
        self.voice = saved
        originalCollections = Set(moment.memberships.compactMap(\.collection?.id))
        collectionIDs = originalCollections
    }

    var hasChanges: Bool {
        caption != original.caption || note != original.note || isFavorite != original.isFavorite
            || (placeWasChosen && place != original.place) || voice != original.voice || collectionIDs != originalCollections
    }

    func loadThumbnail() async {
        guard thumbnail == nil, let path = thumbnailPath, let url = try? library.store.url(for: path),
              let image = try? await library.thumbnails.thumbnail(for: url, maxPixelSize: 400) else { return }
        thumbnail = UIImage(cgImage: image)
    }

    // MARK: Place

    func choose(_ place: ReviewPlace?) {
        self.place = place
        placeWasChosen = true
    }

    func loadNearby() async {}

    func searchPlaces(_ text: String) async -> [PlaceSuggestion] {
        let near = original.place.flatMap { place in
            place.latitude.flatMap { latitude in
                place.longitude.map { GeoPoint(latitude: latitude, longitude: $0, horizontalAccuracy: 1000) }
            }
        }
        return await places.lookup.search(text, near: near)
    }

    func recentPlaces() -> [RecentPlace] {
        places.recents()
    }

    // MARK: Voice note

    func makeVoiceRecording() throws -> VoiceRecording {
        let url = try CaptureFiles.temporaryURL("m4a")
        Task { [transcriber = voiceServices.transcriber] in await transcriber.prepare() }
        return VoiceRecording(recorder: voiceServices.makeRecorder(), url: url, limit: ReviewModel.voiceLimit)
    }

    /// A new recording replaces the voice note when saved. Under half a second is dropped.
    func addVoice(at url: URL, recordedAt: Date) {
        guard let read = VoiceWaveform.read(url, bars: ReviewModel.voiceBars), read.duration >= 0.5 else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        discardRecording()
        voice = .recorded(ReviewVoiceNote(url: url, duration: read.duration, recordedAt: recordedAt))
        transcription = Task { [weak self, transcriber = voiceServices.transcriber] in
            let text = await transcriber.transcribe(url)
            guard let self, !Task.isCancelled, case .recorded(var voice) = self.voice, voice.url == url, let text else { return }
            voice.transcript = text
            self.voice = .recorded(voice)
        }
    }

    func removeVoice() {
        discardRecording()
        voice = nil
    }

    /// A recording that won't be kept: its temporary file goes.
    func discardRecording() {
        transcription?.cancel()
        transcription = nil
        if case let .recorded(recorded) = voice {
            try? FileManager.default.removeItem(at: recorded.url)
            voice = original.voice
        }
    }

    // MARK: Save

    /// Writes what changed. A failure leaves the stored moment as it was.
    func save() async throws {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        await transcription?.value
        let id = id
        var descriptor = FetchDescriptor<Moment>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let moment = try library.context.fetch(descriptor).first else { return }
        let caption = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        moment.title = caption.isEmpty ? nil : caption
        let note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        moment.note = note.isEmpty ? nil : note
        moment.isFavorite = isFavorite
        if placeWasChosen, place != original.place {
            if let location = moment.location { library.context.delete(location) }
            moment.location = place.map {
                MomentLocation(latitude: $0.latitude, longitude: $0.longitude, precision: $0.precision, source: $0.source, placeLabel: $0.label)
            }
        }
        var written: [String] = []
        var replaced: [String] = []
        if voice != original.voice {
            replaced = moment.voiceNotes.map(\.relativePath)
            for old in moment.voiceNotes { library.context.delete(old) }
            moment.voiceNotes = []
            if case let .recorded(recorded) = voice {
                let file = try library.store.store(copyOf: recorded.url, in: .originals)
                written.append(file.relativePath)
                let transcript = recorded.transcript?.trimmingCharacters(in: .whitespacesAndNewlines)
                moment.voiceNotes = [MomentVoiceNote(
                    relativePath: file.relativePath, duration: recorded.duration, recordedAt: recorded.recordedAt,
                    transcript: transcript?.isEmpty == false ? transcript : nil
                )]
            }
        }
        if collectionIDs != originalCollections {
            try CollectionStore(context: library.context).place(id, in: collectionIDs)
        }
        moment.modifiedAt = Date()
        do {
            try library.context.save()
        } catch {
            library.context.rollback()
            for path in written { try? library.store.remove(path) }
            logger.error("Saving the edit failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
        for path in replaced { try? library.store.remove(path) }
        if case let .recorded(recorded) = voice { try? FileManager.default.removeItem(at: recorded.url) }
    }
}
