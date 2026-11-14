import Core
import Persistence
import SwiftUI

/// The viewer's selfie window over a photo or a video (9.24, 9.28): laid out as the camera did, on the media at
/// the screen's full width, and drawn at the size the media is shown here. Moving or resizing it saves it on the
/// moment, which recomposes what grids and sharing show.
struct ViewerSelfieWindow<Content: View>: View {
    let model: MomentViewerModel
    let momentID: UUID
    /// Where the window is, as saved on the moment.
    let saved: PiPLayout
    /// The screen's width and top inset, which the camera's layout counts from.
    let screenWidth: CGFloat
    let topInset: CGFloat
    /// The media's size on screen.
    let shown: CGSize
    @ViewBuilder let content: () -> Content
    @State private var placement = CameraSettings.SelfieWindow()
    @State private var adjustsSelfie = false
    /// The window as saved when the viewer opened, and the placement picked from it. The screen's width and
    /// insets settle over the first layout passes, so until the window is moved it is placed again from what was
    /// saved at the start - never from a frame saved on the way with sizes that were not final yet.
    @State private var opened: PiPLayout?
    @State private var picked: CameraSettings.SelfieWindow?

    var body: some View {
        let layout = SelfieWindowLayout.media(width: screenWidth, aspectRatio: shown.width / shown.height, topInset: topInset)
        AdjustableSelfieWindow(placement: $placement, showsSheet: $adjustsSelfie, layout: layout, id: "viewer.selfieWindow", content: content)
            .frame(width: layout.preview.width, height: layout.preview.height)
            .scaleEffect(shown.width / layout.preview.width, anchor: .topLeading)
            .frame(width: shown.width, height: shown.height, alignment: .topLeading)
            .onChange(of: [screenWidth, topInset, shown.width, shown.height], initial: true) {
                guard picked == nil || placement == picked else { return }
                // What the viewer shows is what sharing exports: a saved layout off every corner (moments saved
                // before 9.17) is kept as the corner and size it is shown at.
                let original = opened ?? saved
                let nearest = layout.placement(nearest: original)
                opened = original
                picked = nearest
                placement = nearest
                model.setWindow(PiPLayout(layout.windowFrame(nearest), source: saved.source), for: momentID)
            }
            .onChange(of: placement) { _, new in
                model.setWindow(PiPLayout(layout.windowFrame(new), source: saved.source), for: momentID)
            }
            .sheet(isPresented: $adjustsSelfie) {
                SelfieWindowSheet(placement: $placement)
            }
    }
}
