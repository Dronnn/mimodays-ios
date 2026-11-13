import SwiftUI

/// Every colour and text style on one screen, for snapshot tests and visual checks.
public struct DesignSystemGallery: View {
    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.sectionGap) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 52), spacing: 8)], spacing: 8) {
                    ForEach(ColorToken.allCases, id: \.self) { token in
                        RoundedRectangle(cornerRadius: Radius.iconBackground)
                            .fill(token.color)
                            .frame(height: 52)
                            .overlay(RoundedRectangle(cornerRadius: Radius.iconBackground).strokeBorder(ColorToken.borderSubtle.color))
                            .accessibilityLabel(Text(verbatim: token.rawValue))
                    }
                }
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(TextStyle.all, id: \.name) { item in
                        Text(verbatim: "\(item.name) Little pieces")
                            .textStyle(item.style)
                            .foregroundStyle(ColorToken.textPrimary.color)
                    }
                }
                Text(verbatim: "Save")
                    .textStyle(.buttonPrimary)
                    .foregroundStyle(ColorToken.textOnCoral.color)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(LinearGradient.actionCoral, in: Capsule())
                    .elevation(.photoFrame)
            }
            .padding(Spacing.screenMargin)
        }
        .background(ColorToken.canvas.color)
    }
}
