import Core
import DesignSystem
import SwiftUI

/// Settings › Appearance › Language: the iPhone's language or one of MimoDays' own, applied at once.
/// Each language is named in its own words, so it can be found from any of them.
struct LanguageSettingsView: View {
    @Bindable var language = AppLanguage.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            BackTitleBar(back: Text("Appearance", bundle: .module), title: Text("Language", bundle: .module)) { dismiss() }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    DataCard {
                        choice(
                            Text("Same as iPhone", bundle: .module, comment: "Language settings: follow the iPhone's language"),
                            detail: Text(verbatim: AppLanguage.nativeName(language.systemCode)),
                            code: nil
                        )
                    }
                    .padding(.horizontal, 16)
                    DataCard {
                        ForEach(AppLanguage.supported, id: \.self) { code in
                            if code != AppLanguage.supported.first { DataSeparator() }
                            choice(Text(verbatim: AppLanguage.nativeName(code)), detail: nil, code: code)
                                .environment(\.layoutDirection, Locale(identifier: code).language.characterDirection == .rightToLeft ? .rightToLeft : .leftToRight)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 20)
                    DataNote(text: Text("iOS's own screens, like permission requests, switch the next time MimoDays opens.", bundle: .module, comment: "Language settings: what follows a switch only after MimoDays opens again"))
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

    private func choice(_ title: Text, detail: Text?, code: String?) -> some View {
        let isSelected = language.code == code
        return Button {
            language.code = code
        } label: {
            HStack(spacing: 8) {
                title.textStyle(.rowTitle)
                    .foregroundStyle(ColorToken.textPrimary.color)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if let detail {
                    detail.textStyle(.rowDetail).foregroundStyle(ColorToken.textTertiary.color)
                }
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
        .accessibilityIdentifier("language.\(code ?? "system")")
    }
}
