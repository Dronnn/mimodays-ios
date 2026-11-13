import Core
import DesignSystem
import SwiftUI

/// C08: the longer note, up to 500 characters. Done keeps it; Cancel drops what changed since opening.
/// What is kept is saved with the review draft, so it survives the app being closed.
struct NoteEditorView: View {
    let model: ReviewModel
    @State private var text: String
    @FocusState private var isFocused: Bool
    @Environment(\.dismiss) private var dismiss

    init(model: ReviewModel) {
        self.model = model
        _text = State(initialValue: model.note)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            bar
            HStack(alignment: .top, spacing: 16) {
                thumbnail
                CaptureTimeLabel(time: model.capture.capturedAt)
                    .textStyle(.noteMeta)
                    .foregroundStyle(ColorToken.textBody.color)
                    .padding(.top, 6)
            }
            .padding(.top, 14)
            .padding(.horizontal, 16)
            TextEditor(text: $text)
                .textStyle(.noteBody)
                .foregroundStyle(ColorToken.textPrimary.color)
                .tint(ColorToken.actionCoral.color)
                .scrollContentBackground(.hidden)
                .focused($isFocused)
                .padding(.horizontal, 11)
                .padding(.top, 16)
                .accessibilityLabel(Text("Note", bundle: .module))
                .accessibilityIdentifier("note.text")
                .onChange(of: text) { _, new in
                    if new.count > ReviewModel.noteLimit { text = String(new.prefix(ReviewModel.noteLimit)) }
                }
            Text(verbatim: "\(text.count) / \(ReviewModel.noteLimit)")
                .textStyle(.noteCount)
                .monospacedDigit()
                .foregroundStyle(ColorToken.textTertiary.color)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
                .accessibilityLabel(Text("\(text.count) of \(ReviewModel.noteLimit) characters", bundle: .module))
                .accessibilityIdentifier("note.count")
        }
        .background(ColorToken.canvas.color.ignoresSafeArea())
        .onAppear { isFocused = true }
    }

    /// `Navigation / Editor bar`: Cancel, Note, Done.
    private var bar: some View {
        ZStack {
            Text("Note", bundle: .module)
                .textStyle(.editorTitle)
                .foregroundStyle(ColorToken.textPrimary.color)
                .accessibilityAddTraits(.isHeader)
            HStack {
                Button { dismiss() } label: {
                    Text("Cancel", bundle: .module)
                        .textStyle(.editorCancel)
                        .foregroundStyle(ColorToken.textBody.color)
                        .frame(minHeight: Size.minimumTapTarget)
                }
                .accessibilityIdentifier("note.cancel")
                Spacer()
                Button {
                    model.note = text
                    dismiss()
                } label: {
                    Text("Done", bundle: .module)
                        .textStyle(.editorDone)
                        .foregroundStyle(ColorToken.textLink.color)
                        .frame(minHeight: Size.minimumTapTarget)
                }
                .accessibilityIdentifier("note.done")
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .frame(height: 44)
    }

    /// 72×92 hand-cut thumbnail of the moment.
    private var thumbnail: some View {
        NoteThumbnailBlob()
            .fill(CameraPalette.thumbnailPlaceholder)
            .overlay {
                if let main = model.main {
                    Image(uiImage: main).resizable().scaledToFill().clipShape(NoteThumbnailBlob())
                }
            }
            .frame(width: 72, height: 92)
            .shadow(color: CameraPalette.chipText.opacity(0.1), radius: 3, y: 2)
            .accessibilityHidden(true)
    }
}

/// "Today, 2:37 PM", or the date and time, in the time zone the moment was captured in.
struct CaptureTimeLabel: View {
    let time: CaptureTime

    var body: some View { Self.text(time) }

    static func text(_ time: CaptureTime) -> Text {
        var format = Date.FormatStyle(date: .omitted, time: .shortened)
        format.timeZone = time.timeZone
        var calendar = Calendar.current
        calendar.timeZone = time.timeZone
        if calendar.isDate(time.instant, inSameDayAs: .now) {
            return Text("Today, \(Text(time.instant, format: format))", bundle: .module)
        }
        var full = Date.FormatStyle(date: .abbreviated, time: .shortened)
        full.timeZone = time.timeZone
        return Text(time.instant, format: full)
    }
}
