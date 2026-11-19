import Core
import DesignSystem
import Foundation
import OSLog
import Persistence
import SwiftData
import SwiftUI

/// S08: everything MimoDays keeps on this iPhone goes, and it starts again from onboarding.
@MainActor
struct AppEraser {
    struct Counts: Equatable {
        var moments = 0
        var collections = 0
        var movies = 0
    }

    let context: ModelContext
    let store: MediaStore
    let notifications: any NotificationScheduler
    let drafts: ReviewDraftStore?
    /// Puts every setting of this iPhone back to its first-launch value.
    let resetSettings: @MainActor () -> Void
    /// The app's temporary folder, emptied too (exports, backups and picked photos waiting there); nil leaves it.
    var temporaryDirectory: URL?

    private static let logger = Logger(subsystem: "MimoDays", category: "Storage")

    func counts() -> Counts {
        Counts(
            moments: (try? context.fetchCount(FetchDescriptor<Moment>())) ?? 0,
            collections: (try? context.fetchCount(FetchDescriptor<MomentCollection>())) ?? 0,
            movies: (try? context.fetchCount(FetchDescriptor<MovieProject>())) ?? 0
        )
    }

    /// Surprise notifications and the backup reminder, every record, every file, the capture in review and the settings.
    func eraseEverything() async throws {
        // Surprises, the backup reminder and "Your movie is ready", waiting or already shown.
        let pending = await notifications.pending()
        await notifications.cancel(ids: pending.map(\.id) + [BackupReminder.notificationID])
        await notifications.removeAll()
        do {
            // Children before their parents, so no rule is left pointing at a deleted row.
            try deleteAll(MovieAudioTrack.self)
            try deleteAll(MovieClip.self)
            try deleteAll(ExportJob.self)
            try deleteAll(MovieProject.self)
            try deleteAll(CollectionMembership.self)
            try deleteAll(MomentCollection.self)
            try deleteAll(MomentVoiceNote.self)
            try deleteAll(MomentMedia.self)
            try deleteAll(MomentLocation.self)
            try deleteAll(SurprisePrompt.self)
            try deleteAll(SurpriseSchedule.self)
            try deleteAll(Moment.self)
            try deleteAll(BackupManifest.self)
            try deleteAll(AppPreferences.self)
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        // The records are gone, so the erase goes on to the end: a file that won't go now has no record and
        // launch's orphan sweep takes it.
        do { try store.removeAll() } catch {
            Self.logger.error("Some files stayed after Delete All: \(error.localizedDescription, privacy: .public)")
        }
        if let temporaryDirectory { Self.removeTemporaryFiles(keeping: store.root, in: temporaryDirectory) }
        drafts?.clear()
        resetSettings()
    }

    /// The temporary folder's items, leaving out the media store when it lives there (UI tests).
    static func removeTemporaryFiles(keeping root: URL, in folder: URL) {
        let kept = root.standardizedFileURL.path
        for item in (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [] {
            let path = item.standardizedFileURL.path
            guard path != kept, !kept.hasPrefix(path + "/") else { continue }
            try? FileManager.default.removeItem(at: item)
        }
    }

    private func deleteAll<Model: PersistentModel>(_: Model.Type) throws {
        for model in try context.fetch(FetchDescriptor<Model>()) {
            context.delete(model)
        }
    }
}

extension EnvironmentValues {
    /// S08: erases everything and goes back to onboarding; nil in previews.
    @Entry var appEraser: AppEraser?
    /// What RootView does once everything is gone.
    @Entry var didEraseEverything: @MainActor () -> Void = {}
    /// Help › "Show the introduction again": closes Settings and opens onboarding from its first page.
    @Entry var replayOnboarding: @MainActor () -> Void = {}
}

/// S08 with the app's eraser and App Lock.
struct DeleteAllScreen: View {
    @Environment(\.appEraser) private var eraser
    @Environment(\.didEraseEverything) private var didErase
    @Environment(AppLock.self) private var lock: AppLock?

    var body: some View {
        if let eraser {
            DeleteAllView(counts: eraser.counts()) {
                if let lock, lock.isEnabled {
                    let reason = String(appLocalized: "Face ID reason: delete all data", defaultValue: "Delete all data", bundle: .module, comment: "Why Face ID is asked for: to delete everything in MimoDays")
                    guard await lock.confirm(reason) else { return false }
                }
                do {
                    try await eraser.eraseEverything()
                } catch {
                    return false
                }
                didErase()
                return true
            }
        }
    }
}

/// S08: what goes, Back up first, the typed DELETE, and Delete everything.
struct DeleteAllView: View {
    let counts: AppEraser.Counts
    /// Asks for Face ID if App Lock is on, then erases; false when nothing was deleted.
    let erase: () async -> Bool
    @State var typed = ""
    @State private var isErasing = false
    @State private var failed = false
    @FocusState private var isTyping: Bool
    @Environment(\.dismiss) private var dismiss

    /// The word to type, in the person's language.
    static var word: String {
        String(appLocalized: "Delete all data: the word to type", defaultValue: "DELETE", bundle: .module, comment: "S08: the word typed to confirm deleting everything. Translate it; keep it one short, uppercase word.")
    }

    private var confirmed: Bool {
        typed.trimmingCharacters(in: .whitespaces).compare(Self.word, options: .caseInsensitive) == .orderedSame
    }

    var body: some View {
        VStack(spacing: 0) {
            BackTitleBar(back: Text("Privacy", bundle: .module)) { dismiss() }
            ScrollView {
                VStack(spacing: 0) {
                    ExplainerArt(glyph: .glyphTrash)
                        .accessibilityHidden(true)
                        .padding(.top, 8)
                    Text("Delete all data?", bundle: .module)
                        .textStyle(.displaySheet)
                        .foregroundStyle(ColorToken.textPrimary.color)
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.top, 14)
                    Text(
                        "This removes \(counts.moments) moments, \(counts.collections) collections, \(counts.movies) movie projects and all settings from this iPhone. It can't be undone. Backups saved in Files are not touched.",
                        bundle: .module, comment: "S08: what Delete all data removes"
                    )
                    .textStyle(.sheetBody)
                    .foregroundStyle(ColorToken.textBody.color)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 30)
                    .padding(.top, 10)
                    NavigationLink(value: DataRoute.backup(back: .deleteAll)) {
                        HStack(spacing: 8) {
                            Icon.glyphArchive.image
                                .resizable()
                                .frame(width: 20, height: 20)
                                .accessibilityHidden(true)
                            Text("Back up first", bundle: .module)
                        }
                        .textStyle(.rowTitle)
                        .foregroundStyle(ColorToken.textPrimary.color)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background { ColorToken.surfaceChip.color.mask { Icon.shapeButton.image.resizable() } }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("deleteAll.backup")
                    .padding(.top, 22)
                    Text("Type \(Self.word) to confirm", bundle: .module, comment: "S08: above the field, e.g. 'Type DELETE to confirm'")
                        .textStyle(.control)
                        .foregroundStyle(ColorToken.textPrimary.color)
                        .padding(.top, 30)
                    TextField(text: $typed) { Text(verbatim: "") }
                        .textStyle(.rowTitle)
                        .foregroundStyle(ColorToken.textPrimary.color)
                        .tint(ColorToken.actionCoral.color)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .focused($isTyping)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 48)
                        .background { ColorToken.surfaceCard.color.mask { Icon.shapeButton.image.resizable() } }
                        .accessibilityLabel(Text("Type \(Self.word) to confirm", bundle: .module, comment: "S08: above the field, e.g. 'Type DELETE to confirm'"))
                        .accessibilityIdentifier("deleteAll.field")
                        .padding(.top, 10)
                    if failed {
                        DataNote(text: Text("Nothing was deleted. Try again.", bundle: .module))
                            .padding(.top, 10)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            Button {
                isTyping = false
                isErasing = true
                Task {
                    failed = !(await erase())
                    isErasing = false
                }
            } label: {
                Text("Delete everything", bundle: .module)
            }
            .buttonStyle(.destructive)
            .disabled(!confirmed || isErasing)
            .opacity(confirmed && !isErasing ? 1 : 0.5)
            .accessibilityIdentifier("deleteAll.delete")
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .background(ColorToken.canvas.color.ignoresSafeArea())
    }
}
