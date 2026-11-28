import Core
import Foundation
import OSLog
import Persistence

/// P8.11: where a moment being written waits, so it survives a lock or the app being closed (one at a time).
struct WritingDraftStore: Sendable {
    let url: URL

    func save(_ draft: TextMomentDraft) {
        do {
            let folder = url.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: folder.path) {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            }
            try JSONEncoder().encode(draft).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            Logger(subsystem: "MimoDays", category: "Writing").error("Keeping the written draft failed: \(String(describing: error), privacy: .public)")
        }
    }

    func load() -> TextMomentDraft? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(TextMomentDraft.self, from: data)
    }

    /// When the draft was last written; nil without one.
    var savedAt: Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    func clear() {
        try? FileManager.default.removeItem(at: url)
    }

    static var temporary: WritingDraftStore {
        WritingDraftStore(url: FileManager.default.temporaryDirectory.appending(path: "Writing-\(UUID().uuidString).json"))
    }
}

/// II01-II03: a moment in words. The draft is kept on disk on every change until it's saved or discarded.
@MainActor
@Observable
final class WriteMomentModel: Identifiable, PlaceChoosing {
    let id = UUID()
    private(set) var draft: TextMomentDraft {
        didSet { if !isFinished { drafts?.save(draft) } }
    }

    var caption: String {
        get { draft.caption }
        set { draft.caption = String(newValue.prefix(TextMoment.captionLimit)) }
    }

    var body: String {
        get { draft.body }
        set { draft.body = String(newValue.prefix(TextMoment.bodyLimit)) }
    }

    var tags: [String] {
        get { draft.tags }
        set { draft.tags = newValue }
    }

    var mood: Mood? {
        get { draft.mood }
        set { draft.mood = newValue }
    }

    var place: ReviewPlace? { draft.place }
    var placeWasChosen: Bool { draft.placeWasChosen }
    private(set) var currentPlace: ReviewPlace?
    private(set) var isLocating = false
    private(set) var nearby: [PlaceSuggestion] = []
    private var fix: GeoPoint?
    private var nearbyFix: GeoPoint?
    /// Saved or discarded: a late lookup writes nothing.
    private var isFinished = false

    private let drafts: WritingDraftStore?
    private let places: PlaceServices

    /// A new moment written now, or the one left unfinished (`draft`). `prompt`: a Journaling Suggestion's, the hint
    /// from now on (P8.12).
    init(draft: TextMomentDraft? = nil, now: CaptureTime, drafts: WritingDraftStore?, places: PlaceServices = .simulated, prompt: String? = nil) {
        var start = draft ?? TextMomentDraft(capturedAt: now)
        if let prompt { start.prompt = prompt }
        self.draft = start
        self.drafts = drafts
        self.places = places
        if draft == nil || prompt != nil { drafts?.save(self.draft) }
    }

    /// DD05: the suggestion's prompt, only a hint.
    var prompt: String? { draft.prompt }

    /// Save needs words in the body.
    var canSave: Bool { TextMoment.canSave(draft) }

    /// Cancel asks first once anything was written or picked.
    var hasEdits: Bool {
        !TextMoment.cleaned(draft.body, limit: TextMoment.bodyLimit).isEmpty
            || !TextMoment.cleaned(draft.caption, limit: TextMoment.captionLimit).isEmpty
            || !draft.tags.isEmpty || draft.mood != nil || (draft.placeWasChosen && draft.place != nil)
    }

    func save(with saver: MomentSaver) throws -> Moment {
        let moment = try saver.saveText(draft)
        finish()
        return moment
    }

    func discard() {
        finish()
    }

    private func finish() {
        isFinished = true
        drafts?.clear()
    }

    // MARK: Place

    /// One fix and its city, as Review does; call only with location allowed. A place picked by name wins.
    func locate() async {
        let privacy = places.privacy()
        guard privacy.savesPlace, fix == nil, !isLocating else { return }
        isLocating = true
        defer { isLocating = false }
        guard let fix = try? await places.location.currentLocation(), !isFinished else { return }
        self.fix = fix
        let city = await places.lookup.city(at: fix)
        guard !isFinished else { return }
        currentPlace = ReviewPlace.current(city: city, at: fix, precision: privacy.precision)
        if !draft.placeWasChosen, draft.place == nil { draft.place = currentPlace }
    }

    func choose(_ place: ReviewPlace?) {
        draft.place = place
        draft.placeWasChosen = true
    }

    func loadNearby() async {
        guard let fix, nearbyFix != fix else { return }
        nearbyFix = fix
        nearby = Array(await places.lookup.nearby(fix).prefix(3))
    }

    func searchPlaces(_ text: String) async -> [PlaceSuggestion] {
        await places.lookup.search(text, near: fix)
    }

    func recentPlaces() -> [RecentPlace] {
        places.recents()
    }
}
