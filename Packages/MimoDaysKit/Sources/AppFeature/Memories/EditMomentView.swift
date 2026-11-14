import Core
import DesignSystem
import Persistence
import SwiftData
import SwiftUI

/// M07: Cancel, Edit moment, Save; the picture and its time (fixed), the caption and note, then voice note, place,
/// collections and favourite. Delete moment (9.11) joins with its step.
struct EditMomentView: View {
    @Bindable var model: EditMomentModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.permissions) private var permissions
    @Environment(\.openURL) private var openURL
    @State private var confirmsDiscard = false
    @State private var choosesVoice = false
    @State private var choosesPlace = false
    @State private var choosesCollections = false
    @State private var recording: VoiceRecording?
    @State private var microphoneOff = false
    @State private var saveFailed = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.top, 14)
                captionField
                    .padding(.top, 20)
                noteField
                    .padding(.top, 10)
                rows
                    .padding(.top, 20)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .top, spacing: 0) { bar }
        .background(ColorToken.canvas.color.ignoresSafeArea())
        .interactiveDismissDisabled(model.hasChanges)
        .task { await model.loadThumbnail() }
        .confirmationDialog(Text("Discard your changes?", bundle: .module), isPresented: $confirmsDiscard, titleVisibility: .visible) {
            Button(role: .destructive) {
                model.discardRecording()
                dismiss()
            } label: { Text("Discard changes", bundle: .module) }
            Button(role: .cancel) {} label: { Text("Keep editing", bundle: .module) }
        }
        .confirmationDialog(Text("Voice note", bundle: .module), isPresented: $choosesVoice, titleVisibility: .hidden) {
            Button { recordVoice() } label: { Text("Record again", bundle: .module) }
            Button(role: .destructive) { model.removeVoice() } label: { Text("Delete voice note", bundle: .module) }
        }
        .sheet(item: $recording) { recording in
            VoiceRecordingSheet(recording: recording) { model.addVoice(at: $0.url, recordedAt: $0.startedAt) }
        }
        .sheet(isPresented: $choosesPlace) {
            PlaceSheet(model: model, showsCurrent: false)
        }
        .sheet(isPresented: $choosesCollections) {
            CollectionPickerSheet(library: model.library, selection: $model.collectionIDs)
        }
        .sheet(isPresented: $microphoneOff) {
            PermissionExplainerView(screen: .microphoneOff) {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            } secondary: {
                microphoneOff = false
            }
        }
        .alert(Text("Couldn't save the changes", bundle: .module), isPresented: $saveFailed) {
            Button(role: .cancel) {} label: { Text("Keep editing", bundle: .module) }
        } message: {
            Text("Nothing was changed. Try again in a moment.", bundle: .module)
        }
    }

    /// `Navigation / Editor bar`: Cancel, Edit moment, Save.
    private var bar: some View {
        ZStack {
            Text("Edit moment", bundle: .module)
                .textStyle(.editorTitle)
                .foregroundStyle(ColorToken.textPrimary.color)
                .accessibilityAddTraits(.isHeader)
            HStack {
                Button(action: cancel) {
                    Text("Cancel", bundle: .module)
                        .textStyle(.editorCancel)
                        .foregroundStyle(ColorToken.textBody.color)
                        .frame(minHeight: Size.minimumTapTarget)
                }
                .accessibilityIdentifier("edit.cancel")
                Spacer()
                Button(action: save) {
                    Text("Save", bundle: .module)
                        .textStyle(.editorDone)
                        .foregroundStyle(ColorToken.textLink.color)
                        .frame(minHeight: Size.minimumTapTarget)
                }
                .disabled(model.isSaving)
                .accessibilityIdentifier("edit.save")
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .frame(height: 44)
        .background(ColorToken.canvas.color)
    }

    /// The picture and when it was taken, which stay as they are.
    private var header: some View {
        HStack(alignment: .top, spacing: 18) {
            NoteThumbnailBlob()
                .fill(CameraPalette.thumbnailPlaceholder)
                .overlay {
                    if let thumbnail = model.thumbnail {
                        Image(uiImage: thumbnail).resizable().scaledToFill().clipShape(NoteThumbnailBlob())
                    }
                }
                .frame(width: 94, height: 118)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                MomentViewer.time(model.captured, date: true)
                    .textStyle(.noteMeta)
                    .foregroundStyle(ColorToken.textBody.color)
                Group {
                    if model.mediaType == .video {
                        Text("The video and its time can't be changed.", bundle: .module)
                    } else {
                        Text("The photo and its time can't be changed.", bundle: .module)
                    }
                }
                .textStyle(.rowCaption)
                .foregroundStyle(ColorToken.textTertiary.color)
            }
            .padding(.top, 8)
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var captionField: some View {
        TextField(text: $model.caption, axis: .vertical) {
            Text("Add a few words (optional)", bundle: .module)
                .foregroundStyle(ColorToken.textTertiary.color)
        }
        .lineLimit(1...4)
        .textStyle(.reviewField)
        .foregroundStyle(ColorToken.textPrimary.color)
        .tint(ColorToken.actionCoral.color)
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(minHeight: 60, alignment: .topLeading)
        .background(FieldBlob().fill(ColorToken.surfaceCard.color))
        .accessibilityLabel(Text("Caption", bundle: .module))
        .accessibilityIdentifier("edit.caption")
    }

    private var noteField: some View {
        TextField(text: $model.note, axis: .vertical) {
            Text("Add a note", bundle: .module)
                .foregroundStyle(ColorToken.textTertiary.color)
        }
        .lineLimit(2...12)
        .textStyle(.noteBody)
        .foregroundStyle(ColorToken.textPrimary.color)
        .tint(ColorToken.actionCoral.color)
        .onChange(of: model.note) { _, new in
            if new.count > ReviewModel.noteLimit { model.note = String(new.prefix(ReviewModel.noteLimit)) }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(FieldBlob().fill(ColorToken.surfaceCard.color))
        .accessibilityLabel(Text("Note", bundle: .module))
        .accessibilityIdentifier("edit.note")
    }

    private var rows: some View {
        VStack(spacing: 0) {
            row(icon: .glyphMic, title: Text("Voice note", bundle: .module), id: "edit.voice") {
                if let voice = model.voice {
                    Text(Duration.seconds(voice.duration.rounded()), format: .time(pattern: .minuteSecond))
                } else {
                    Text("Add", bundle: .module)
                }
            } action: {
                model.voice == nil ? recordVoice() : (choosesVoice = true)
            }
            row(icon: .glyphPin, title: Text("Place", bundle: .module), id: "edit.place") {
                if let label = model.place?.label {
                    Text(label)
                } else {
                    Text("None", bundle: .module)
                }
            } action: {
                choosesPlace = true
            }
            row(icon: .glyphCollection, title: Text("Collections", bundle: .module), id: "edit.collections") {
                collectionNames
            } action: {
                choosesCollections = true
            }
            favoriteRow
        }
        .background(ColorToken.surfaceCard.color, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    /// "Lena's firsts", "Lena's firsts and Walks", or None.
    @ViewBuilder
    private var collectionNames: some View {
        let names = ((try? model.library.context.fetch(FetchDescriptor<MomentCollection>(sortBy: [SortDescriptor(\.sortOrder)]))) ?? [])
            .filter { model.collectionIDs.contains($0.id) }
            .map(\.title)
        if names.isEmpty {
            Text("None", bundle: .module)
        } else {
            Text(names, format: .list(type: .and))
        }
    }

    private var favoriteRow: some View {
        Toggle(isOn: $model.isFavorite) {
            HStack(spacing: 14) {
                disc(.glyphHeart)
                Text("Favorite", bundle: .module)
                    .textStyle(.rowTitle)
                    .foregroundStyle(ColorToken.textPrimary.color)
            }
        }
        .tint(ColorToken.actionCoral.color)
        .padding(.leading, 14)
        .padding(.trailing, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 64)
        .accessibilityIdentifier("edit.favorite")
    }

    /// A 64 pt row: peach disc with a glyph, the title, its value and a chevron.
    private func row(
        icon: Icon, title: Text, id: String, @ViewBuilder value: () -> some View, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                disc(icon)
                title
                    .textStyle(.rowTitle)
                    .foregroundStyle(ColorToken.textPrimary.color)
                Spacer(minLength: 8)
                value()
                    .textStyle(.rowCaption)
                    .foregroundStyle(ColorToken.textSecondary.color)
                    .lineLimit(1)
                Icon.glyphChevron.image
                    .frame(width: 20, height: 20)
                    .foregroundStyle(ColorToken.textPrimary.color)
                    .flipsForRightToLeftLayoutDirection(true)
                    .accessibilityHidden(true)
            }
            .padding(.leading, 14)
            .padding(.trailing, 12)
            .padding(.vertical, 12)
            .frame(minHeight: 64)
            .overlay(alignment: .bottom) {
                ColorToken.separator.color.frame(height: 1).padding(.leading, 64)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(id)
    }

    private func disc(_ icon: Icon) -> some View {
        icon.image
            .resizable()
            .frame(width: 20, height: 20)
            .foregroundStyle(ColorToken.textPrimary.color)
            .frame(width: 36, height: 36)
            .background(ColorToken.accentPeach.color, in: Circle())
            .accessibilityHidden(true)
    }

    // MARK: Actions

    private func cancel() {
        if model.hasChanges {
            confirmsDiscard = true
        } else {
            dismiss()
        }
    }

    private func save() {
        Task {
            do {
                try await model.save()
                dismiss()
            } catch {
                saveFailed = true
            }
        }
    }

    /// The system prompt the first time; once it is off, the way to Settings.
    private func recordVoice() {
        Task {
            var status = await permissions.status(of: .microphone)
            if status == .notDetermined { status = await permissions.request(.microphone) }
            guard status.isUsable else {
                microphoneOff = true
                return
            }
            guard let recording = try? model.makeVoiceRecording(), recording.start() else { return }
            self.recording = recording
        }
    }
}
