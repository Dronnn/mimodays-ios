import Core
import DesignSystem
import Persistence
import SwiftUI

/// II01-II03: Cancel, Write a moment, Save; the time it was started, an optional caption, the words with their count,
/// then Place, Tags and Mood. Nothing here asks for the camera, the microphone or Photos.
struct WriteMomentView: View {
    @State var model: WriteMomentModel
    /// Called after the save, before the sheet closes.
    var onSaved: @MainActor (Moment) -> Void = { _ in }
    @Environment(\.momentSaver) private var saver
    @Environment(\.mediaLibrary) private var library
    @Environment(\.permissions) private var permissions
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var asker = PermissionAsker()
    @State private var locationAllowed = false
    @State private var choosesPlace = false
    @State private var editsTags = false
    @State private var choosesMood = false
    @State private var confirmsCancel = false
    @State private var isSaving = false
    @State private var saveFailed = false
    @FocusState private var focus: Field?

    private enum Field { case caption, body }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            bar
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    CaptureTimeLabel(time: model.draft.capturedAt)
                        .textStyle(.noteMeta)
                        .foregroundStyle(ColorToken.textBody.color)
                        .padding(.horizontal, 4)
                    captionField
                        .padding(.top, 12)
                    bodyField
                        .padding(.top, 14)
                    count
                        .padding(.top, 8)
                    ChipFlow(spacing: 8, lineSpacing: 2) { chips }
                        .padding(.top, 8)
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(ColorToken.canvas.color.ignoresSafeArea())
        // Swiping it away would lose the words without asking.
        .interactiveDismissDisabled()
        .task {
            // Location is never asked for here: only after a tap on Place.
            guard await permissions.status(of: .location).isUsable else { return }
            locationAllowed = true
            await model.locate()
        }
        .sheet(isPresented: $choosesPlace) {
            PlaceSheet(model: model, showsCurrent: locationAllowed)
        }
        .sheet(isPresented: $editsTags) {
            TagEditorSheet(tags: $model.tags, recent: library.map { Tags.recent(in: $0.context) } ?? [])
        }
        .sheet(isPresented: $choosesMood) {
            MoodPickerSheet(mood: $model.mood)
        }
        .permissionExplainers(asker)
        .confirmationDialog(Text("Discard this moment?", bundle: .module), isPresented: $confirmsCancel, titleVisibility: .hidden) {
            Button(role: .cancel) {} label: { Text("Keep writing", bundle: .module) }
            Button(role: .destructive) {
                model.discard()
                dismiss()
            } label: { Text("Discard", bundle: .module) }
        }
        .alert(Text("This moment didn't save", bundle: .module), isPresented: $saveFailed) {
            Button(role: .cancel) {} label: { Text("Not now", bundle: .module) }
            Button { save() } label: { Text("Try again", bundle: .module) }
                .keyboardShortcut(.defaultAction)
        } message: {
            Text("Nothing is lost. Try again in a moment.", bundle: .module)
        }
        .accessibilityIdentifier("textMoment")
    }

    /// `Navigation / Editor bar`: Cancel, Write a moment, Save (coral once there are words).
    private var bar: some View {
        TitleBar {
            Button(action: cancel) {
                Text("Cancel", bundle: .module)
                    .textStyle(.editorCancel)
                    .foregroundStyle(ColorToken.textBody.color)
                    .frame(minHeight: Size.minimumTapTarget)
            }
            .accessibilityIdentifier("textMoment.cancel")
        } title: {
            Text("Write a moment", bundle: .module)
                .textStyle(.editorTitle)
                .foregroundStyle(ColorToken.textPrimary.color)
                .accessibilityAddTraits(.isHeader)
        } trailing: {
            Button(action: save) {
                Text("Save", bundle: .module)
                    .textStyle(.editorDone)
                    .foregroundStyle(model.canSave ? ColorToken.textLink.color : ColorToken.textLink.color.opacity(0.4))
                    .frame(minHeight: Size.minimumTapTarget)
            }
            .disabled(!model.canSave || isSaving)
            .accessibilityIdentifier("textMoment.save")
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .frame(height: 44)
    }

    private var captionField: some View {
        TextField(text: $model.caption, axis: .vertical) {
            Text("Add a few words (optional)", bundle: .module)
                .foregroundStyle(ColorToken.textTertiary.color)
        }
        .lineLimit(1...3)
        .textStyle(.reviewField)
        .foregroundStyle(ColorToken.textPrimary.color)
        .tint(ColorToken.actionCoral.color)
        .focused($focus, equals: .caption)
        .submitLabel(.next)
        .onSubmit { focus = .body }
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
        .frame(minHeight: 52, alignment: .leading)
        .background(FieldBlob().fill(ColorToken.surfaceCard.color))
        .accessibilityLabel(Text("Caption", bundle: .module))
        .accessibilityIdentifier("textMoment.caption")
    }

    private var bodyField: some View {
        TextField(text: $model.body, axis: .vertical) {
            Text("Write what you want to remember…", bundle: .module)
                .foregroundStyle(ColorToken.textTertiary.color)
        }
        .lineLimit(9...)
        .textStyle(.noteBody)
        .foregroundStyle(ColorToken.textPrimary.color)
        .tint(ColorToken.actionCoral.color)
        .focused($focus, equals: .body)
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(minHeight: 230, alignment: .topLeading)
        .background(FieldBlob().fill(ColorToken.surfaceCard.color))
        .accessibilityLabel(Text("Your words", bundle: .module))
        .accessibilityValue(Text(model.body))
        .accessibilityIdentifier("textMoment.body")
    }

    private var count: some View {
        Text(verbatim: "\(model.body.count.formatted(.number.locale(locale))) / \(TextMoment.bodyLimit.formatted(.number.locale(locale)))")
            .textStyle(.noteCount)
            .monospacedDigit()
            .foregroundStyle(ColorToken.textTertiary.color)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .accessibilityLabel(Text("\(model.body.count) of \(TextMoment.bodyLimit) characters", bundle: .module))
    }

    /// Place, then Tags (each tag once there are some) and Mood, as in Review.
    @ViewBuilder
    private var chips: some View {
        ReviewChip(icon: .glyphPin, title: model.place.map { $0.label.map { Text($0) } ?? Text("Current location", bundle: .module) } ?? Text("Place", bundle: .module), isFilled: model.place != nil, action: choosePlace)
            .accessibilityLabel(Text("Place", bundle: .module))
            .accessibilityValue(model.place.map { $0.label.map { Text($0) } ?? Text("Current location", bundle: .module) } ?? Text("None", bundle: .module))
            .accessibilityIdentifier("textMoment.place")
        if model.tags.isEmpty {
            ReviewChip(mark: "#", title: Text("Tags", bundle: .module)) { editsTags = true }
                .accessibilityIdentifier("textMoment.tags")
        } else {
            ForEach(model.tags, id: \.self) { tag in
                ReviewChip(title: Text(verbatim: "#" + tag), isFilled: true) { editsTags = true }
                    .accessibilityLabel(Text("Tags", bundle: .module))
                    .accessibilityValue(Text(verbatim: TagList.text(model.tags)))
            }
            .accessibilityIdentifier("textMoment.tags")
        }
        ReviewChip(mark: model.mood?.emoji ?? "🙂", title: model.mood?.name ?? Text("Mood", bundle: .module), isFilled: model.mood != nil) {
            choosesMood = true
        }
        .accessibilityLabel(Text("Mood", bundle: .module))
        .accessibilityValue(model.mood?.name ?? Text("None", bundle: .module))
        .accessibilityIdentifier("textMoment.mood")
    }

    private func choosePlace() {
        guard !isSaving, !asker.isAsking else { return }
        focus = nil
        Task {
            let status = await asker.request(.location, using: permissions)
            locationAllowed = status.isUsable
            choosesPlace = true
            if status.isUsable { await model.locate() }
        }
    }

    private func cancel() {
        guard !isSaving else { return }
        if model.hasEdits {
            focus = nil
            confirmsCancel = true
        } else {
            model.discard()
            dismiss()
        }
    }

    private func save() {
        guard !isSaving, model.canSave else { return }
        isSaving = true
        focus = nil
        do {
            guard let saver else { throw SaveError.failed }
            let moment = try model.save(with: saver)
            onSaved(moment)
            dismiss()
        } catch {
            saveFailed = true
        }
        isSaving = false
    }
}
