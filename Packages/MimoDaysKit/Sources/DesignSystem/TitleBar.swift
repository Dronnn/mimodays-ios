import SwiftUI

/// A top bar's three parts, laid out as the system navigation bar does: the title centred on the screen while it
/// fits between the buttons, otherwise moved off centre and then truncated, never under a button. The buttons keep
/// their size up to a third of the width each and stay on one line, however long the translation.
public struct TitleBar<Leading: View, Title: View, Trailing: View>: View {
    private let leading: Leading
    private let title: Title
    private let trailing: Trailing

    public init(
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder title: () -> Title,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) {
        self.leading = leading()
        self.title = title()
        self.trailing = trailing()
    }

    public var body: some View {
        // Each part in its own container, so a missing button still counts as one (empty) subview.
        TitleBarLayout {
            ZStack { leading }
            ZStack { title }
            ZStack { trailing }
        }
        .lineLimit(1)
    }
}

private struct TitleBarLayout: Layout {
    private let spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? subviews.reduce(2 * spacing) { $0 + $1.sizeThatFits(.unspecified).width }
        let frames = frames(width: width, subviews: subviews)
        return CGSize(width: width, height: frames.map(\.height).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (subview, frame) in zip(subviews, frames(width: bounds.width, subviews: subviews)) {
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.midY),
                anchor: .leading,
                proposal: ProposedViewSize(width: frame.width, height: frame.height)
            )
        }
    }

    /// Leading, title and trailing: x and width along the bar, and each part's height.
    private func frames(width: CGFloat, subviews: Subviews) -> [CGRect] {
        guard subviews.count == 3 else { return subviews.map { _ in .zero } }
        let side = ProposedViewSize(width: width / 3, height: nil)
        let leading = subviews[0].sizeThatFits(side)
        let trailing = subviews[2].sizeThatFits(side)
        let room = max(0, width - leading.width - trailing.width - 2 * spacing)
        let titleWidth = min(subviews[1].sizeThatFits(.unspecified).width, room)
        let title = subviews[1].sizeThatFits(ProposedViewSize(width: titleWidth, height: nil))
        // Centred on the bar when the buttons leave room for it, otherwise as close to the centre as they allow.
        let lowest = leading.width + spacing
        let highest = width - trailing.width - spacing - titleWidth
        let titleX = min(max((width - titleWidth) / 2, lowest), max(lowest, highest))
        return [
            CGRect(x: 0, y: 0, width: leading.width, height: leading.height),
            CGRect(x: titleX, y: 0, width: titleWidth, height: title.height),
            CGRect(x: width - trailing.width, y: 0, width: trailing.width, height: trailing.height),
        ]
    }
}
