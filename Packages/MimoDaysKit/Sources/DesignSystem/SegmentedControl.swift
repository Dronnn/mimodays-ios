import SwiftUI

/// `Control / Segmented`: hand-cut chip track with a peach pill under the selected option.
/// Options share the width equally, or with `fitsLabels` each gets its label's width plus an equal share of the
/// rest (C04's corners). Labels stop growing at 1.35x so a word never breaks across lines; they may wrap to two
/// lines and the track grows with them.
public struct SegmentedControl<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [Value]
    let fitsLabels: Bool
    let label: (Value) -> Text
    @Namespace private var pill

    public init(selection: Binding<Value>, options: [Value], fitsLabels: Bool = false, label: @escaping (Value) -> Text) {
        _selection = selection
        self.options = options
        self.fitsLabels = fitsLabels
        self.label = label
    }

    public var body: some View {
        let layout = fitsLabels ? AnyLayout(FittedSegmentsLayout()) : AnyLayout(HStackLayout(spacing: 0))
        layout {
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

/// Each segment gets its ideal width plus an equal share of the spare width. When the labels don't fit on one
/// line, the segments share the width equally and wrap.
struct FittedSegmentsLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let widths = widths(proposal.width, subviews)
        let height = zip(subviews, widths).map { $0.sizeThatFits(ProposedViewSize(width: $1, height: nil)).height }.max() ?? 0
        return CGSize(width: widths.reduce(0, +), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        var x = bounds.minX
        for (subview, width) in zip(subviews, widths(bounds.width, subviews)) {
            subview.place(at: CGPoint(x: x, y: bounds.minY), proposal: ProposedViewSize(width: width, height: bounds.height))
            x += width
        }
    }

    private func widths(_ total: CGFloat?, _ subviews: Subviews) -> [CGFloat] {
        let ideal = subviews.map { $0.sizeThatFits(.unspecified).width }
        guard let total, !subviews.isEmpty else { return ideal }
        let spare = total - ideal.reduce(0, +)
        let count = CGFloat(subviews.count)
        return spare >= 0 ? ideal.map { $0 + spare / count } : Array(repeating: total / count, count: subviews.count)
    }
}
