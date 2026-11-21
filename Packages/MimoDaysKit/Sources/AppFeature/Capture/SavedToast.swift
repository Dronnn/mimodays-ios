import DesignSystem
import SwiftUI

/// C12: "Saved to today" after a save, back where the capture started. Dark in both appearances.
struct SavedToast: View {
    /// What was saved: today's moment, a Then & Now repeat (GG06), or one whose original went before it saved.
    enum Kind: Equatable {
        case today
        case thenNow
        case originalGone

        var text: Text {
            switch self {
            case .today: Text("Saved to today", bundle: .module)
            case .thenNow: Text("Saved. It's in Then & Now on the card's back", bundle: .module)
            case .originalGone: Text("The original is no longer available. This moment was saved.", bundle: .module)
            }
        }

        var announcement: String {
            switch self {
            case .today: String(appLocalized: "Saved to today", bundle: .module)
            case .thenNow: String(appLocalized: "Saved. It's in Then & Now on the card's back", bundle: .module)
            case .originalGone: String(appLocalized: "The original is no longer available. This moment was saved.", bundle: .module)
            }
        }
    }

    var kind = Kind.today

    var body: some View {
        HStack(spacing: 10) {
            Icon.glyphCheck.image
                .frame(width: 24, height: 24)
                .foregroundStyle(CameraPalette.chipText)
                .frame(width: 28, height: 28)
                .background(CameraPalette.chip, in: Circle())
            kind.text
                .textStyle(.reviewField)
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                .foregroundStyle(CameraPalette.cream)
        }
        .padding(.leading, 10)
        .padding(.trailing, 20)
        .frame(minHeight: 48)
        .background(CameraPalette.background, in: Capsule())
        .shadow(color: CameraPalette.background.opacity(0.25), radius: 9, y: 6)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("savedToast")
    }
}
