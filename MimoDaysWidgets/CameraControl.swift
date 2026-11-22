import AppIntents
import SwiftUI
import WidgetFeature
import WidgetKit

/// P8.1: MimoDays Camera in Control Center, on the Lock Screen and the Action button; it opens the app's camera.
struct CameraControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.mrmaier.MimoDays.camera") {
            ControlWidgetButton(action: OpenCameraIntent()) {
                Label { Text(WidgetText.camera) } icon: { Image(systemName: "camera") }
            }
        }
        .displayName(WidgetText.camera)
    }
}
