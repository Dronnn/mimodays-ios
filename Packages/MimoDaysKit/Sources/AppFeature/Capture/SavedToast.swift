import DesignSystem
import SwiftUI

/// C12: "Saved to today" after a save, back where the capture started. Dark in both appearances.
struct SavedToast: View {
    var body: some View {
        HStack(spacing: 10) {
            Icon.glyphCheck.image
                .frame(width: 24, height: 24)
                .foregroundStyle(CameraPalette.chipText)
                .frame(width: 28, height: 28)
                .background(CameraPalette.chip, in: Circle())
            Text("Saved to today", bundle: .module)
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
