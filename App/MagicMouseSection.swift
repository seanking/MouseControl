import MouseControlKit
import SwiftUI

/// The menu section for a connected Magic Mouse. macOS handles its gestures and scrolling,
/// so tracking speed is the only setting.
struct MagicMouseSection: View {
    let mouse: MagicMouse
    let settings: SettingsStore
    @State private var speed = 1.0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            DeviceHeader(name: mouse.name, battery: mouse.battery, lowBatteryThreshold: settings.lowBatteryThreshold)
            Divider()
            SettingSlider(
                title: "Tracking speed",
                valueLabel: speed.formatted(.number.precision(.fractionLength(2))),
                value: $speed,
                range: TrackingSpeed.range,
                snap: TrackingSpeed.snap,
                onEditingChanged: { editing in
                    // Apply on release: changing the speed mid-drag would change how the drag moves.
                    if !editing { mouse.setTrackingSpeed(speed) }
                }
            )
        }
        .onAppear { speed = mouse.trackingSpeed }
    }
}
