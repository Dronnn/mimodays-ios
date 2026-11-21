import Core
import Foundation
import Persistence

/// P8.11: a moment written in words, without the camera. Saved as `MediaType.text`, the body in `note`, the caption
/// in `title`, no files.
struct TextMomentDraft: Codable, Equatable {
    var capturedAt: CaptureTime
    var caption = ""
    var body = ""
    var place: ReviewPlace?
    var tags: [String] = []
    var mood: Mood?
    /// A place or "No place" was picked: a late location fix no longer fills it in.
    var placeWasChosen = false
}

enum TextMoment {
    static let captionLimit = 80
    static let bodyLimit = 500
    /// What a tile or a movie's paper card shows; the full body stays on the Memory Card.
    static let excerptLimit = 140

    /// Trimmed at both ends and cut to `limit` characters (whole characters, never half an emoji).
    static func cleaned(_ text: String, limit: Int) -> String {
        String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(limit)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Save needs words in the body.
    static func canSave(_ draft: TextMomentDraft) -> Bool {
        !cleaned(draft.body, limit: bodyLimit).isEmpty
    }

    /// Share text: the caption over the words, nothing else (no place, tags or mood).
    static func shareText(title: String?, body: String?) -> String {
        [title, body].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    /// The start of the body on one line, with "…" when there is more.
    static func excerpt(_ body: String, limit: Int = excerptLimit) -> String {
        let flat = body.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " ")
        guard flat.count > limit else { return flat }
        let cut = flat.prefix(limit)
        // At a word break when there is one in the last part.
        let end = cut.lastIndex(where: \.isWhitespace).flatMap { cut.distance(from: cut.startIndex, to: $0) > limit * 2 / 3 ? $0 : nil } ?? cut.endIndex
        return cut[..<end].trimmingCharacters(in: .whitespaces) + "…"
    }
}

extension MomentSaver {
    /// P8.11: saves the written moment; nothing is saved without words in the body.
    func saveText(_ draft: TextMomentDraft) throws -> Moment {
        let body = TextMoment.cleaned(draft.body, limit: TextMoment.bodyLimit)
        guard !body.isEmpty else { throw SaveError.failed }
        let moment = Moment(captured: draft.capturedAt, origin: .manual, mediaType: .text, promptID: nil, createdAt: clock.now())
        let caption = TextMoment.cleaned(draft.caption, limit: TextMoment.captionLimit)
        moment.title = caption.isEmpty ? nil : caption
        moment.note = body
        moment.tags = draft.tags
        moment.mood = draft.mood
        context.insert(moment)
        if let place = draft.place {
            moment.location = MomentLocation(
                latitude: place.latitude, longitude: place.longitude, precision: place.precision, source: place.source, placeLabel: place.label
            )
        }
        do {
            try context.save()
        } catch {
            context.rollback()
            throw SaveError.failed
        }
        return moment
    }
}
