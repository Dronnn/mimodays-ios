import DesignSystem
import SwiftUI

/// U16's light parallax: the picture drifts against the scroll, a few percent of its height.
struct MosaicParallax: ViewModifier {
    let isOn: Bool

    func body(content: Content) -> some View {
        content.visualEffect { content, proxy in
            let viewport = proxy.bounds(of: .scrollView(axis: .vertical)) ?? .zero
            // -1 a screen above the middle, 1 a screen below it.
            let progress = viewport.height > 0 ? (proxy.size.height / 2 - viewport.midY) / viewport.height : 0
            return content.offset(y: isOn ? -min(max(progress, -1), 1) * proxy.size.height * 0.05 : 0)
        }
    }
}
