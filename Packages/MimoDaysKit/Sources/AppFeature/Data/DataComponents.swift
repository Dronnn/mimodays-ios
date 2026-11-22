import DesignSystem
import SwiftUI

/// `List card`: rows on the cream card, 22 pt corners.
struct DataCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .background(ColorToken.surfaceCard.color, in: HandCutCard())
    }
}

/// The plum hairline between a card's rows, from `leading` to the card's right edge.
struct DataSeparator: View {
    var leading: CGFloat = 16

    var body: some View {
        ColorToken.separator.color.frame(height: 1).padding(.leading, leading)
    }
}

/// A row's 16/700 title over its 13.5/500 line.
struct DataRowLabel: View {
    let title: Text
    var detail: Text?
    var detailColor = ColorToken.textSecondary
    var titleColor = ColorToken.textPrimary

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            title.textStyle(.rowTitle).foregroundStyle(titleColor.color)
            if let detail {
                detail.textStyle(.meta).foregroundStyle(detailColor.color)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// The 20 pt chevron at a row's end.
struct DataChevron: View {
    var body: some View {
        Icon.glyphChevron.image
            .resizable()
            .frame(width: 20, height: 20)
            .foregroundStyle(ColorToken.textPrimary.color)
            .flipsForRightToLeftLayoutDirection(true)
            .accessibilityHidden(true)
    }
}

/// A peach disc with a 20 pt glyph, the title, an optional value and a chevron (E06, E08, E09).
struct DataIconRow: View {
    let icon: Icon
    let title: Text
    var detail: Text?
    var value: Text?
    var opens = true
    var iconInk = ColorToken.textPrimary
    var titleColor = ColorToken.textPrimary
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // At accessibility sizes the value goes under the title, so neither breaks mid-word.
        let stacksValue = typeSize.isAccessibilitySize
        HStack(spacing: 0) {
            icon.image
                .resizable()
                .frame(width: 20, height: 20)
                .foregroundStyle(iconInk.color)
                .frame(width: 36, height: 36)
                .background(Circle().fill(ColorToken.accentPeach.color))
                .accessibilityHidden(true)
                .padding(.trailing, 14)
            VStack(alignment: .leading, spacing: 3) {
                DataRowLabel(title: title, detail: detail, titleColor: titleColor)
                if stacksValue, let value { value.textStyle(.rowValue).foregroundStyle(ColorToken.textTertiary.color) }
            }
            Spacer(minLength: 8)
            HStack(spacing: 6) {
                if !stacksValue, let value { value.textStyle(.rowValue).foregroundStyle(ColorToken.textTertiary.color) }
                if opens { DataChevron() }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, detail == nil ? 8 : 10)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// A title, its line under it, and a coral switch (E01-E03, E05).
struct DataToggleRow: View {
    let title: Text
    var detail: Text?
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) { DataRowLabel(title: title, detail: detail) }
            .tint(ColorToken.actionCoral.color)
            .padding(.horizontal, 16)
            .padding(.vertical, detail == nil ? 8 : 10)
            .frame(minHeight: 52)
    }
}

/// The 13.5 pt note under a card or a choice.
struct DataNote: View {
    let text: Text

    var body: some View {
        text.textStyle(.meta)
            .foregroundStyle(ColorToken.textSecondary.color)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

enum DataFormat {
    /// "today", "yesterday", "18 days ago" - in days, as E06 and E09 count them.
    static func ago(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
        switch days {
        case ...0: return String(appLocalized: "Days since the backup: today", defaultValue: "today", bundle: .module, comment: "When the last backup was made: today")
        case 1: return String(appLocalized: "Days since the backup: yesterday", defaultValue: "yesterday", bundle: .module, comment: "When the last backup was made: yesterday")
        default: return String(appLocalized: "\(days) days ago", bundle: .module, comment: "When the last backup was made, in days")
        }
    }
}
