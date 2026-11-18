import Core
import DesignSystem
import SwiftUI

/// Settings › Appearance › Fonts: the headline and handwriting faces for the language in use, each kept per
/// language (Andrew, 2026-11-18). The sample on top shows the choice at once; each face is listed in itself, and only
/// faces that have every letter of the language are offered.
struct FontSettingsView: View {
    @Environment(AppearancePreferences.self) private var preferences: AppearancePreferences?
    @Environment(\.typefaces) private var typefaces
    @Environment(\.dismiss) private var dismiss
    @ScaledMetric(relativeTo: .body) private var headingSize: CGFloat = 21
    @ScaledMetric(relativeTo: .body) private var handSize: CGFloat = 20
    /// The language whose faces these are: the one in use.
    var language = AppLanguage.shared.current

    var body: some View {
        VStack(spacing: 0) {
            BackTitleBar(back: Text("Appearance", bundle: .module), title: Text("Fonts", bundle: .module)) { dismiss() }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    DataCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Your life, in little pieces.", bundle: .module)
                                .textStyle(.displaySheet)
                                .foregroundStyle(ColorToken.textPrimary.color)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("Catch a moment", bundle: .module)
                                .textStyle(.captureLabel)
                                .foregroundStyle(ColorToken.textBody.color)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(18)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("fonts.sample")
                    .padding(.horizontal, 16)
                    section(.heading)
                        .padding(.top, 26)
                    section(.hand)
                        .padding(.top, 26)
                    DataNote(text: Text(
                        "MimoDays keeps fonts for each language. These are for \(AppLanguage.nativeName(language)).",
                        bundle: .module, comment: "Settings › Appearance › Fonts: the note at the bottom; the argument is the language's own name, e.g. 'Русский'"
                    ))
                    .padding(.horizontal, 22)
                    .padding(.top, 12)
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
        .background(ColorToken.canvas.color.ignoresSafeArea())
    }

    private func section(_ role: Typeface.Role) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if role == .heading {
                    Text("Headings", bundle: .module, comment: "Settings › Appearance › Fonts: section title over the fonts for titles")
                } else {
                    Text("Handwriting", bundle: .module, comment: "Settings › Appearance › Fonts: section title over the handwritten fonts for captions and notes")
                }
            }
            .textStyle(.labelCaps)
            .foregroundStyle(ColorToken.textSecondary.color)
            .accessibilityAddTraits(.isHeader)
            .padding(.horizontal, 22)
            .padding(.bottom, 8)
            DataCard {
                let faces = Typefaces.options(role, language: language)
                ForEach(faces) { face in
                    if face != faces.first { DataSeparator() }
                    row(face, role: role)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func row(_ face: Typeface, role: Typeface.Role) -> some View {
        let isSelected = (role == .heading ? typefaces.heading : typefaces.hand) == face
        return Button {
            choose(face, role: role)
        } label: {
            HStack(spacing: 8) {
                // The language's own name in the face shows how its letters look; the face's name beside it.
                Text(verbatim: AppLanguage.nativeName(language))
                    .font(face.sample(role, size: role == .heading ? headingSize : handSize))
                    .foregroundStyle(ColorToken.textPrimary.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 8)
                Text(verbatim: face.name)
                    .textStyle(.rowDetail)
                    .foregroundStyle(ColorToken.textTertiary.color)
                    .lineLimit(1)
                if isSelected {
                    Icon.glyphCheck.image
                        .resizable()
                        .frame(width: 22, height: 22)
                        .foregroundStyle(ColorToken.textLink.color)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(minHeight: Size.rowHeight)
            .contentShape(Rectangle())
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("fonts.\(role == .heading ? "heading" : "hand").\(face.id)")
    }

    private func choose(_ face: Typeface, role: Typeface.Role) {
        guard let preferences else { return }
        var pick = preferences.value.fonts[language] ?? FontPick()
        switch role {
        case .heading: pick.heading = face.id
        case .hand: pick.hand = face.id
        }
        preferences.value.fonts[language] = pick
    }
}
