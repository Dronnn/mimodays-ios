import DesignSystem
import SwiftUI

/// P8.12 DD04: back in MimoDays with the suggestion picked in Apple's picker - pick its photo, or write from its
/// prompt; or it has nothing to add, or couldn't be opened. `finish` closes the sheet with what comes next.
struct JournalingSheet: View {
    @Bindable var model: JournalingModel
    let finish: (JournalingModel.Next?) -> Void
    @AccessibilityFocusState private var headingFocused: Bool

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 14), count: 3)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            BackTitleBar(back: Text("Cancel", bundle: .module)) { finish(nil) }
                .accessibilityIdentifier("journaling.cancel")
            content
        }
        .background(ColorToken.surfaceSheet.color.ignoresSafeArea())
        // Opened once; Try again opens it again.
        .task { if model.phase == .loading, model.pick == nil { await model.start() } }
        .accessibilityIdentifier("journaling")
    }

    private var heading: some View {
        Text("Add to MimoDays", bundle: .module, comment: "P8.12 DD04 title: a Journaling Suggestion back in the app")
            .textStyle(.displaySheet)
            .foregroundStyle(ColorToken.textPrimary.color)
            .accessibilityAddTraits(.isHeader)
            .accessibilityFocused($headingFocused)
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .onAppear { headingFocused = true }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            heading
            Spacer()
            HStack(spacing: 10) {
                ProgressView()
                Text("Opening suggestion…", bundle: .module, comment: "P8.12: while the picked Journaling Suggestion is read")
                    .textStyle(.rowCaption)
                    .foregroundStyle(ColorToken.textSecondary.color)
            }
            .frame(maxWidth: .infinity)
            Spacer()
        case .ready:
            ready
        case .unsupported:
            heading
            notice(Text("There's nothing to add from this suggestion.", bundle: .module, comment: "P8.12: the picked suggestion has no photo and no prompt")) {
                Button { finish(.write(prompt: nil)) } label: { Text("Write a moment", bundle: .module) }
                    .buttonStyle(.primary)
                    .accessibilityIdentifier("journaling.write")
                Button { finish(.chooseAgain) } label: {
                    Text("Choose another suggestion", bundle: .module, comment: "P8.12: back to Apple's Journaling Suggestions picker")
                }
                .buttonStyle(.text)
                .accessibilityIdentifier("journaling.chooseAgain")
            }
        case .failed:
            heading
            notice(Text("Couldn't open this suggestion", bundle: .module, comment: "P8.12: the picked suggestion's photos couldn't be read")) {
                Button { Task { await model.start() } } label: { Text("Try again", bundle: .module) }
                    .buttonStyle(.primary)
                    .accessibilityIdentifier("journaling.retry")
            }
        }
    }

    private var ready: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    heading
                    if let pick = model.pick {
                        summary(pick)
                            .padding(.horizontal, 20)
                            .padding(.top, 14)
                    }
                    Group {
                        if model.use == .photo {
                            Text("From Journaling Suggestions. Pick the photo for this moment.", bundle: .module, comment: "P8.12 DD04, under the suggestion's day and title")
                        } else {
                            Text("From Journaling Suggestions. Write a moment with this prompt as a hint.", bundle: .module, comment: "P8.12 DD04, a writing prompt")
                        }
                    }
                        .textStyle(.rowCaption)
                        .foregroundStyle(ColorToken.textSecondary.color)
                        .padding(.horizontal, 20)
                        .padding(.top, 4)
                    if model.offersBoth {
                        SegmentedControl(selection: $model.use, options: [.photo, .prompt]) { use in
                            switch use {
                            case .photo: Text("Use a photo", bundle: .module, comment: "P8.12: the suggestion has photos and a prompt")
                            case .prompt: Text("Write from this prompt", bundle: .module, comment: "P8.12: the suggestion has photos and a prompt")
                            }
                        }
                        .accessibilityIdentifier("journaling.use")
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                    }
                    if model.use == .photo {
                        LazyVGrid(columns: columns, spacing: 14) {
                            ForEach(model.pick?.photos.indices ?? 0..<0, id: \.self) { tile($0) }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 18)
                    } else if let prompt = model.prompt {
                        promptCard(prompt)
                            .padding(.horizontal, 16)
                            .padding(.top, 18)
                    }
                }
                .padding(.bottom, 16)
            }
            // Dimmed until a photo is chosen.
            Button { finish(model.next) } label: { Text("Continue", bundle: .module) }
                .buttonStyle(WizardButtonStyle())
                .disabled(!model.canContinue)
                .accessibilityIdentifier("journaling.continue")
                .padding(.horizontal, Spacing.screenMargin)
                .padding(.bottom, 8)
        }
    }

    /// "Saturday, Nov 21 · Republic Square".
    private func summary(_ pick: JournalingPick) -> some View {
        Group {
            if let date = pick.date {
                Text("\(Text(date, format: .dateTime.weekday(.wide).month(.abbreviated).day())) · \(pick.title)", bundle: .module, comment: "P8.12 DD04: the suggestion's day, then its title")
            } else {
                Text(pick.title)
            }
        }
        .textStyle(TextStyle(.body, size: 14, weight: 700, relativeTo: .subheadline))
        .foregroundStyle(ColorToken.textPrimary.color)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tile(_ index: Int) -> some View {
        let isOn = model.chosen == index
        return Button { model.chosen = index } label: {
            Color(hex: 0xC9B8AA)
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    if let image = model.thumbnails[index] { Image(uiImage: image).resizable().scaledToFill() }
                }
                .clipShape(StripTile.shape(index &* 7 + 1))
                .overlay { SelectionMark(isOn: isOn, cornerRadius: 12) }
                .contentShape(Rectangle())
                .environment(\.layoutDirection, .leftToRight)
        }
        .buttonStyle(.plain)
        .accessibilityElement()
        .accessibilityLabel(Text("Photo \(index + 1)", bundle: .module, comment: "P8.12 DD04: one of the suggestion's photos, by its place"))
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("journaling.asset")
    }

    private func promptCard(_ prompt: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Icon.glyphSparkle.image
                .resizable()
                .frame(width: 20, height: 20)
                .foregroundStyle(ColorToken.textPrimary.color)
                .accessibilityHidden(true)
            Text(prompt)
                .textStyle(.handSmall)
                .foregroundStyle(ColorToken.textPrimary.color)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(FieldBlob().fill(ColorToken.accentPeach.color))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("journaling.prompt")
    }

    private func notice(_ message: Text, @ViewBuilder actions: () -> some View) -> some View {
        VStack(spacing: 14) {
            Spacer()
            message
                .textStyle(.body)
                .foregroundStyle(ColorToken.textSecondary.color)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            Spacer()
            actions()
        }
        .padding(.horizontal, Spacing.screenMargin)
        .padding(.bottom, 8)
    }
}
