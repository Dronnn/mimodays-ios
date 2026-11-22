import Core
import Foundation
import Persistence
import SwiftData

/// rev-capture 18: a saved voice note without its words gets them once iOS has the speech model, so Save never
/// waits for them and a note made before the first download isn't left without (the transcript is optional, doc 01 §15).
@MainActor
enum SavedTranscripts {
    static func fill(_ momentID: UUID, context: ModelContext, store: MediaStore, transcriber: any VoiceTranscriber) async {
        guard let note = voiceNote(momentID, in: context), note.transcript == nil, let url = try? store.url(for: note.relativePath) else { return }
        let path = note.relativePath
        await transcriber.prepare()
        guard let text = await transcriber.transcribe(url) else { return }
        // Still the same note: it may have been replaced or deleted meanwhile.
        guard let note = voiceNote(momentID, in: context), note.relativePath == path, note.transcript == nil else { return }
        note.transcript = text
        try? context.save()
    }

    private static func voiceNote(_ momentID: UUID, in context: ModelContext) -> MomentVoiceNote? {
        var descriptor = FetchDescriptor<Moment>(predicate: #Predicate { $0.id == momentID })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor).first)?.voiceNotes.first
    }
}
