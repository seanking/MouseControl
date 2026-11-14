import MouseControlKit
import SwiftUI

/// The menu section for a connected Logitech mouse: everything configured over HID++.
struct LogitechMouseSection: View {
    let mouse: LogitechMouse
    let settings: SettingsStore
    @State private var dpiIndex: Double = 0
    @State private var draggingDPI = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            DeviceHeader(
                name: mouse.name,
                battery: mouse.battery,
                lowBatteryThreshold: settings.lowBatteryThreshold,
                error: mouse.lastError
            )
            Divider()
            wheelSection
            Divider()
            pointerSection
            Divider()
            buttonsSection
        }
        .onAppear { syncDPIIndex() }
        .onChange(of: mouse.currentDPI) { syncDPIIndex() }
        .onChange(of: mouse.supportedDPIs) { syncDPIIndex() }
    }

    private var wheelSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingDropdown(title: "Scroll direction", selection: Binding(
                get: { settings.mouseScrollDirection },
                set: { mouse.setScrollDirection($0) }
            )) {
                Text("Natural").tag(SettingsStore.ScrollDirection.natural)
                Text("Standard").tag(SettingsStore.ScrollDirection.standard)
            }
            if mouse.scrollFallbackActive {
                Text("Using event-tap fallback for scroll inversion.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            SettingDropdown(title: "Thumb wheel", selection: Binding(
                get: { settings.thumbWheelInverted },
                set: { mouse.setThumbWheelInverted($0) }
            )) {
                Text("Normal").tag(false)
                Text("Inverted").tag(true)
            }
        }
    }

    private var pointerSection: some View {
        let dpis = mouse.supportedDPIs
        return SettingSlider(
            title: "Pointer speed",
            valueLabel: dpiLabel,
            value: $dpiIndex,
            range: 0...Double(max(dpis.count - 1, 1)),
            snap: { $0.rounded() },
            onEditingChanged: { editing in
                draggingDPI = editing
                // Apply once on release instead of on every step of the drag.
                if !editing, dpis.indices.contains(Int(dpiIndex)) {
                    mouse.setDPI(dpis[Int(dpiIndex)])
                }
            }
        )
        .disabled(dpis.count < 2)
    }

    private var buttonsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingToggle(
                title: "Back/Forward buttons",
                detail: "Sends ⌘[ and ⌘] (works in Safari)",
                isOn: Binding(get: { settings.backForwardEnabled }, set: { mouse.setBackForward($0) })
            )
            SettingDropdown(title: "Thumb button", detail: thumbButtonDetail, selection: Binding(
                get: { settings.thumbButtonAction },
                set: { mouse.setThumbButtonAction($0) }
            )) {
                ForEach(SettingsStore.ThumbButtonAction.allCases, id: \.self) { action in
                    Text(action.title).tag(action)
                }
            }
            SettingToggle(
                title: "Drag to switch Spaces",
                detail: mouse.gestureSwipeAvailable == false
                    ? "Not available on this device"
                    : "Hold the thumb button and drag left or right (sends ⌃← / ⌃→)",
                isOn: Binding(get: { settings.thumbButtonSwipeSpaces }, set: { mouse.setThumbButtonSwipeSpaces($0) })
            )
            .disabled(mouse.gestureSwipeAvailable == false)
        }
    }

    private var thumbButtonDetail: String? {
        if mouse.gestureButtonAvailable == false { return "Not available on this device" }
        return settings.thumbButtonAction.systemShortcut.map { "Sends \($0)" }
    }

    private var dpiLabel: String {
        let dpis = mouse.supportedDPIs
        if draggingDPI, dpis.indices.contains(Int(dpiIndex)) { return "\(dpis[Int(dpiIndex)]) DPI" }
        if let dpi = mouse.currentDPI { return "\(dpi) DPI" }
        return "—"
    }

    private func syncDPIIndex() {
        guard !draggingDPI else { return }
        let dpis = mouse.supportedDPIs
        guard let target = mouse.currentDPI ?? settings.dpi,
              let snapped = AdjustableDPIFeature.snap(target, to: dpis),
              let index = dpis.firstIndex(of: snapped) else { return }
        dpiIndex = Double(index)
    }
}
