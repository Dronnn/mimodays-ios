import SwiftUI
import WidgetKit

/// P8.2: On this day and Random memory on the Home Screen, and the MimoDays Camera control (P8.1).
@main
struct MimoDaysWidgetsBundle: WidgetBundle {
    var body: some Widget {
        OnThisDayWidget()
        RandomMemoryWidget()
        CameraControl()
    }
}
