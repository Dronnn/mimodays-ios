import SwiftUI

/// `Control / Segmented`: hand-cut chip track with a peach pill under the selected option.
/// Options share the width equally. Labels stop growing at 1.35x so a word never breaks across lines;
/// they may wrap to two lines and the track grows with them.
public struct SegmentedControl<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [Value]
    let label: (Value) -> Text
    @Namespace private var pill

    public init(selection: Binding<Value>, options: [Value], label: @escaping (Value) -> Text) {
        _selection = selection
        self.options = options
        self.label = label
    }

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { option in
                let isSelected = option == selection
                Button {
                    withAnimation(.snappy) { selection = option }
                } label: {
                    label(option)
                        .textStyle(TextStyle(.nunito, size: 14, weight: isSelected ? 700 : 600, relativeTo: .subheadline, maximumScale: 1.35))
                        .foregroundStyle((isSelected ? ColorToken.textLink : .textPrimary).color)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background {
                            if isSelected {
                                Icon.shapeSegmentPill.image
                                    .resizable()
                                    .foregroundStyle(ColorToken.accentPeach.color)
                                    .padding(.horizontal, 2)
                                    .padding(.vertical, 4)
                                    .matchedGeometryEffect(id: "pill", in: pill)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .background {
            Icon.shapeSegmentTrack.image.resizable().foregroundStyle(ColorToken.surfaceChip.color)
        }
        .accessibilityElement(children: .contain)
    }
}
