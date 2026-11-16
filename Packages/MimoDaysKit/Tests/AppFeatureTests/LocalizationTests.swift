@testable import AppFeature
import Foundation
import Persistence
import Testing

struct LocalizationTests {
    private static let missing = "\u{0}missing"

    /// Keys used directly as `Text("…", bundle: .module)`.
    private static let literalKeys = ["Collections", "New collection", "No collections yet", "Group moments that belong together, like a trip or someone's firsts.", "Name", "A collection only groups moments. Removing a moment from it, or deleting the collection, never deletes the moment.", "Create", "Add moments", "Remove from collection", "Rename", "Delete collection", "More", "Rename collection", "Delete “%@”?", "Its moments stay in Memories.", "Collection detail: %@ · %@",
        "No favorites yet", "Tap the heart on any moment to keep it here.", "Search moments", "Clear", "Removes this place", "Photos", "Videos", "Voice", "Filters", "Filters · %lld", "Places", "Moments · %lld", "Place detail: %@ · %@", "matched in caption", "matched in note", "matched in voice note", "matched in place", "No matches", "No moments match these filters.", "Nothing matches “%@” in photos.", "Nothing matches “%@” in videos.", "Nothing matches “%@”.", "Nothing matches “%@” with these filters.", "No matches message: %@ %@", "Search looks at notes, voice-note words and places.", "Search all moments", "Search", "All", "From", "To", "Any time", "Up to today", "Has a voice note", "Has a written note", "Favorites only", "Reset", "Show %lld moments",
        "%lld years back", "Years ago and year: %@ · %@", "On this day subtitle: %@", "Nothing on this day yet", "Moments from today will be here next year.",
        "Select", "Select moments", "%lld selected", "Select all", "Deselect all", "Collect",
        "Delete this moment?", "Delete these %lld moments?", "The photo, selfie window, note and voice note move to Recently deleted. You can bring them back within 30 days.", "The video, selfie window, note and voice note move to Recently deleted. You can bring them back within 30 days.", "They move to Recently deleted with their notes and voice notes. You can bring them back within 30 days.", "Used in %lld movie drafts. It will be skipped there.", "Used in %lld movie drafts. They will be skipped there.", "Delete moment", "Delete %lld moments", "Delete", "Recently deleted", "Moments are deleted for good after 30 days. They are not shown anywhere else in the app.", "Delete all", "Recover all", "Delete %lld moments for good?", "This can't be undone.", "%lld days", "Removed in %lld days", "Deleted today.", "Deleted %lld days ago.", "Will be removed in %lld days.", "Recover", "Delete now", "Delete this moment for good?",
        "Edit", "Edit moment", "Discard your changes?", "Discard changes", "Delete voice note",
        "Couldn't save the changes", "Nothing was changed. Try again in a moment.", "The photo and its time can't be changed.",
        "The video and its time can't be changed.", "Add a note", "Add", "Photo with selfie", "Share", "Favorite", "Voice note · %@", "Stops it", "Plays it", "Pause", "Play", "Sound off", "Sound on", "Playback position",
        "Timeline", "Calendar", "Shows the whole year", "Calendar day: %@ · %@",
        "Selected day: %@ · %@", "Calendar month: %@ · %@", "Next month", "Previous month", "Next year", "Previous year",
        "Day summary: %@ · %@", "%lld days with moments", "Day label today: %@", "Day label yesterday: %@", "No memories yet",
        "Moments you capture on Today show up here, grouped by day.", "Description is favorite", "Description has voice note", "Today headline", "surprise", "Your first moment will live here.",
        "what you see", "Catch a moment", "Catch your first moment", "Catch the surprise", "Your %@", "On this day",
        "Years ago and count: %@ · %@", "%lld years ago", "%lld moments", "Make my movie",
        "Your story starts with one moment", "%lld moments saved", "with selfie", "Yesterday, %@", "Day and time: %@ · %@",
        "Your next surprise is on its way", "A surprise moment is ready",
        "That surprise has passed. Catch a moment anyway?", "Surprises are paused", "Surprises are paused until tomorrow",
        "Surprises are paused until %@", "Turn on little surprises", "Open", "Resume", "Turn on",
        "Settings", "Done", "Close", "A little surprise", "Skip", "Page %lld of %lld",
        "Back", "When should MimoDays surprise you?", "Pick how often and when. The exact time is always a surprise.",
        "How often", "On these days", "Earliest", "Latest", "Surprises only arrive between these times. Focus modes still apply.",
        "Enable reminders", "Maybe later", "Your first surprise is on its way.", "No reminders for now. That's okay.",
        "You can still capture moments whenever you like. To get surprises later, turn on notifications for MimoDays in Settings.",
        "Open iOS Settings", "Ready for your first little moment?", "Try the camera. Save the photo or video only if you like it.",
        "Capture my first moment", "I'll do it later", "Your first moment is here.",
        "It lives on this iPhone. Come back tomorrow, or whenever a surprise arrives.", "View my moments", "Today, %@",
        "Camera settings", "Flash", "Sound", "Selfie window", "On", "Off", "Switch camera", "Take photo", "Record video",
        "Stop recording", "Recording", "Tap to stop",
        "This iPhone can use one camera at a time. Tap ↻ to switch between you and the world.",
        "Opens in", "Video length", "Record sound", "Shutter sound", "In silent mode, photos never make a sound.", "Camera", "Photo", "Video",
        "Top left", "Top right", "Bottom left", "Bottom right", "Small", "Medium", "Large", "Reset to default",
        "Adjust selfie window",
        "Videos will be silent. Turn on the microphone in Settings to add sound.",
        "Not enough space to record. Free up some space on this iPhone and try again.",
        "The camera is busy with a call or another app. It comes back on its own.",
        "This iPhone is too warm for the camera right now. It comes back once it cools down.",
        "The camera paused for a moment. It comes back on its own.",
        "The camera isn't available right now. Close and try again in a moment.",
        "That one didn't come out. Try again.",
        "Retake", "Add a few words (optional)", "Caption", "Save", "Record again", "Save %lld seconds",
        "Plays the video", "Pauses the video", "Saved to today", "Manage storage", "Try again", "Not now",
        "Not enough space to save", "This moment is kept until you free up about %@. Nothing is lost.",
        "This moment didn't save", "Nothing is lost. Try again in a moment.",
        "Note", "Cancel", "Retake and drop the note?", "Keep editing", "%lld of %lld characters",
        "Voice note", "%@ of %@", "%@ copy", "Remove voice note", "Pause voice note", "Play voice note", "Transcript in quotes: %@",
        // Movies (Phase 11).
        "New movie", "Movie", "Make a movie of these", "Drafts", "No movies yet", "Turn a month, a trip or a whole year of moments into a short film.", "Make a movie", "%@ is ready", "%lld moments from %lld days.", "About %lld minutes.", "Make it", "Not now", "Draft", "Edited %@", "%@ · %@ · %@", "%@, the whole year", "Last month", "This year", "Last year", "These dates", "This collection", "This place", "This choice", "Movie period: this collection", "Movie period: this place", "Movie period: these dates", "Step %lld of 3", "What's it about?", "%@ · %@", "Dates", "Pick a start and an end", "A collection", "A place", "Choose moments", "Not enough yet", "%@ has %lld moments. A movie needs at least 5 so it doesn't feel stretched. We never repeat or pad clips.", "Choose more dates", "Catch a moment now", "Source", "Which dates?", "Pick a day", "The end is before the start. Pick a later end date.", "Previous month", "Next month", "Which collection?", "How long, what shape?", "No collections yet. Make one in Memories.", "Which place?", "No moments have a place yet.", "Length", "Shape", "%lld minutes", "Quick", "Short", "Full", "Custom", "about 1 min", "3 to 5 min", "every moment · %@", "you choose", "Photos and videos that don't match the shape", "Fill the frame", "Show all of it", "9:16 · Phone", "16:9 · TV", "1:1 · Square", "Which moments?", "All · %lld", "Picked · %lld", "Build the movie", "Tap the moments you want in the movie. It needs at least 5.", "We picked %lld of %lld, spread evenly across %@. Tap to add or remove.", "Next", "Unnamed place", "Back",
        "Transcribed on this iPhone", "Retake and drop the voice note?", "Retake and drop the notes?",
        "Place", "Current location", "None", "Finding where you are…", "Current location · city only", "Nearby",
        "Used %lld times", "No place", "No places found", "Search places",
        "Places are stored on this iPhone only. You can choose how precise they are in Settings.",
        "%@ · Surprise", "Surprise · %@", "Surprise moment, %@", "Imported · %@", "Imported from Photos, %@",
        "A call stopped the recording at %@. The part before the call is kept.",
        "The recording stopped at %@ when you left MimoDays. The part before is kept.",
        "This iPhone got too warm, so the recording stopped at %@. The part before is kept.",
        "This iPhone ran out of space, so the recording stopped at %@. The part before is kept.",
        "The recording stopped at %@. The part before is kept.",
        // Movie editor, export and movie page (Phase 11).
        "Music", "Choose another file", "Remove music", "Export", "This movie can't play right now.", "Movie preview", "Undo", "Clips", "Text",
        "Audio", "Cut", "Fade", "Atmosphere", "A few words", "Transition title: clip %lld", "the start", "the text card", "Trim", "Replace", "Remove", "Fill", "Show all",
        "Selfie window for this clip", "This clip has no selfie.", "Bottom", "Hidden", "Date on each clip", "Place on each clip",
        "Title at the start", "Sound from clips", "Voice notes", "Your own audio file from Files. Fades in and out.", "Seconds on screen", "Start",
        "End", "Replace with", "Every moment is already in the movie.", "Title", "Movie title", "Show it at the start", "Export movie", "Quality",
        "Privacy", "Date in the file", "Exact place in the file",
        "Captions you added are part of the picture. File details are hidden unless you turn them on.", "4K", "Making your movie", "Progress",
        "You can leave this screen or lock the phone. We'll let you know when it's ready.", "Play the movie", "Your movie is ready",
        "Saved to Photos", "Save to Photos", "Save to Files", "Couldn't save to Photos", "OK", "Allow MimoDays to add to your photos in Settings.",
        "Something went wrong. Try again.", "The movie couldn't be finished", "Free up space", "Back to the editor",
        "Something went wrong while making it.\nYour draft is safe.", "Saved", "Project", "Delete movie and project",
        "Copies saved to Photos or Files stay there.", "Rename movie", "Delete this movie and its project?", "Duplicate", "Changes make a new version",
        "Position", "Move earlier", "Move later", "%lld of %lld clips", "Clip %lld of %lld",
        "Shows for %@ s", "%@ – %@ · %@ s", "About %@. You have %@ free.", "About %@.", "%@ · %@ · %lld clips", "%@ · about %@ left",
        "Make it in 720p (about %@)", "There isn't enough free space on this iPhone.\nIt needs about %@ more.\nYour draft is safe.",
        "Movie · %@ · %@ · %@ · made %@",
        // Backup, restore and storage (Phase 12).
        "Time for a backup", "Your newest moments are only on this iPhone. A backup keeps them safe.", "Backup", "Back up now",
        "Restore from a backup", "Remind me to back up",
        "Backups are files you keep. MimoDays never uploads them anywhere. If this iPhone is lost, a backup is the only way to get your moments back.",
        "No backup yet", "Every moment is in it.", "Never", "Weekly", "Monthly", "Back up everything",
        "One file with every moment, note, voice note, collection and movie project. Keep it in Files, on a Mac or on a drive. It can be restored on any iPhone with MimoDays.",
        "Moments, notes and voice", "Movie projects", "Rendered movies", "can be made again from projects", "Create backup",
        "Creating your backup", "Keep MimoDays open. If you leave, the backup pauses and continues when you come back.", "Choose where to save",
        "Packing files", "Checking the backup", "In progress", "Backup saved", "Every file checked and readable", "Show in Files",
        "The backup couldn't be made", "Something went wrong while packing it. Nothing was changed. Try again.", "Restoring your moments",
        "Restore", "Add what's missing", "Nothing here is changed or removed", "Replace everything", "This iPhone will match the backup exactly",
        "checked, no problems", "some files are damaged", "Skipped. The rest of the backup is fine.", "Left as they are", "Skipped moments",
        "This isn't a MimoDays backup", "Update MimoDays first", "Not enough space", "The backup couldn't be restored",
        "Choose a .mimodays file made with Back up now. A file that was cut off while copying can't be read either.",
        "This backup was made by a newer MimoDays. Update the app, then restore it.", "Nothing on this iPhone was changed. Try again.", "Storage",
        "Clear temporary files", "Moments", "photos, videos, selfie windows", "can be made again", "Temporary files", "previews and thumbnails",
        "Days since the backup: today", "Days since the backup: yesterday", "%lld days ago", "Last backup %@",
        "%lld moments are only on this iPhone.", "%lld new moments since then are only on this iPhone.", "About %@ · %@ free",
        "Collecting %lld moments", "Packing files · %@", "%lld moments packed", "Saved to Files › %@",
        "There isn't enough free space on this iPhone to make it. It needs about %@ more.", "Backup from %@",
        "%lld moments · %lld collections · %lld movie projects · %@", "%lld are already here. %lld are new.", "Add %lld moments",
        "Replace with %lld moments", "%lld of %lld moments restored", "%lld files are damaged", "%lld were already here",
        "Nothing was restored. This iPhone needs about %@ more free space.", "%@ used by MimoDays", "%lld · %@",
        "Choosing where to save",
        // Moment and selection export (Phase 12).
        "MimoDays %lld moments", "Export %lld moments", "Export moment", "As you saw it", "Separate originals",
        "The camera's own files, front and back separately.", "One video with the selfie window, exactly as in MimoDays.",
        "One photo with the selfie window, exactly as in MimoDays.", "as an audio file", "as a text file", "Exact place",
        "hidden unless you turn it on", "Separate files", "One archive (.zip)",
        "An archive keeps everything together with a list of dates, notes and places that any computer can read.",
        "Each moment as its own files, named by the date and time it was taken.", "Include", "Notes", "Original camera files",
        "front and back separately", "Exact places", "Exporting %@", "Couldn't export",
        "There isn't enough free space on this iPhone. It needs about %@ more.",
        // Import from Photos (Phase 12).
        "Import", "Import from Photos", "Import %lld", "Importing %@", "%lld photos", "%lld videos", "%lld photos and videos",
        "Each one goes to the day it was taken and is marked \"From Photos\". They have no selfie window. The originals stay in Photos.",
        "Keep the place from Photos", "city level", "Already in MimoDays", "%lld skipped", "Some files couldn't be imported",
        "The others are in Memories. Try the rest again from Photos.",
        // Settings (Phase 13); the plain Text keys are found by the source scan.
        "Not before", "Not after", "Until %@", "Selfie window size in a phrase: small",
        "Selfie window size in a phrase: medium", "Selfie window size in a phrase: large",
        "Lock with %@", "Recently deleted always asks for %@ when App Lock is on.", "Remove the place from %lld moments?", "Unlock with %@",
        "your passcode", "Unlock MimoDays", "Turn on App Lock", "Open Recently deleted", "Face ID reason: delete all data", "Privacy row: delete all data", "Type %@ to confirm",
        "Delete all data: the word to type", "Version %@",
        "This removes %lld moments, %lld collections, %lld movie projects and all settings from this iPhone. It can't be undone. Backups saved in Files are not touched.",
    ]

    private static var resourceKeys: [String] {
        let resources = MainTab.allCases.map(\.title)
            + PermissionScreen.allCases.flatMap { [$0.title, $0.message, $0.primaryAction, $0.secondaryAction] }
            + OnboardingPage.allCases.flatMap { [$0.title, $0.message, $0.primaryAction] }
            + SurpriseFrequency.allCases.map(\.label)
            + CameraSettings.VideoLength.allCases.map(\.settingsLabel)
            + SurpriseFrequency.allCases.map { frequency in
                var schedule = ReminderSchedule()
                schedule.frequency = frequency
                return schedule.summary(calendar: .current, locale: .current)
            }
            + (OnboardingPage.allCases.flatMap(\.artLayers) + FirstCaptureView.artLayers).compactMap { layer -> LocalizedStringResource? in
                guard case let .text(.localized(resource), _, _, _, _, _) = layer else { return nil }
                return resource
            }
        return resources.map(\.key)
    }

    @Test(arguments: resourceKeys + literalKeys)
    func everyUsedKeyIsInTheCatalog(key: String) {
        #expect(Bundle.module.localizedString(forKey: key, value: Self.missing, table: nil) != Self.missing)
    }

    /// Every plain `Text("…", bundle: .module)` in AppFeature, so a new key can't be forgotten in `literalKeys`.
    @Test func everyLiteralInTheSourcesIsInTheCatalog() throws {
        let sources = URL(filePath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Sources/AppFeature")
        let files = try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        var keys: Set<String> = []
        for case let url as URL in files where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            for match in text.matches(of: /Text\("((?:[^"\\]|\\[^(])*)", bundle: \.module/) {
                keys.insert(String(match.1).replacing("\\\"", with: "\"").replacing("\\n", with: "\n"))
            }
        }
        #expect(keys.count > 100)
        for key in keys.sorted() {
            let isInCatalog = Bundle.module.localizedString(forKey: key, value: Self.missing, table: nil) != Self.missing
            #expect(isInCatalog, "not in the catalog: \(key)")
        }
    }

    /// Translators need a comment for every string, and English must be complete.
    @Test func everyCatalogEntryHasCommentAndEnglish() throws {
        let url = URL(filePath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Sources/AppFeature/Resources/Localizable.xcstrings")
        let catalog = try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: url))
        #expect(catalog.sourceLanguage == "en")
        for (key, entry) in catalog.strings {
            #expect(entry.comment?.isEmpty == false, "no comment: \(key)")
            let english = entry.localizations?["en"]
            let units = english?.units ?? []
            #expect(!units.isEmpty && units.allSatisfy { $0.state == "translated" }, "no English: \(key)")
        }
    }

    private struct Catalog: Decodable {
        struct Entry: Decodable {
            /// A string, or its plural or device (iPad) variants, which can nest.
            final class Localization: Decodable {
                struct Unit: Decodable { var state: String }
                struct Variations: Decodable {
                    var plural: [String: Localization]?
                    var device: [String: Localization]?
                }
                var stringUnit: Unit?
                var variations: Variations?

                var units: [Unit] {
                    if let stringUnit { return [stringUnit] }
                    let variants = Array((variations?.plural ?? [:]).values) + Array((variations?.device ?? [:]).values)
                    let units = variants.map(\.units)
                    return units.contains(where: \.isEmpty) ? [] : units.flatMap { $0 }
                }
            }

            var comment: String?
            var localizations: [String: Localization]?
        }

        var sourceLanguage: String
        var strings: [String: Entry]
    }
}
