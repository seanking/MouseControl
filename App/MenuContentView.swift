import MouseControlKit
import SwiftUI

struct MenuBarLabel: View {
    let controller: DeviceController

    var body: some View {
        let symbol = controller.connection == .connected ? "computermouse.fill" : "computermouse"
        if controller.settings.showBatteryInMenuBar, let battery = controller.battery {
            HStack(spacing: 2) {
                Image(systemName: symbol)
                Text("\(battery.percentage)%")
            }
        } else {
            Image(systemName: symbol)
        }
    }
}

struct MenuContentView: View {
    @Bindable var controller: DeviceController
    @State private var dpiIndex: Double = 0
    @State private var draggingDPI = false

    private var settings: SettingsStore { controller.settings }
    /// Shared width for leading header icons so the text beside them lines up.
    private let iconWidth: CGFloat = 18
    /// Shared width for dropdowns so they match each other exactly.
    private let dropdownWidth: CGFloat = 110

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            permissionWarnings
            Divider()
            wheelSection
            Divider()
            pointerSection
            Divider()
            buttonsSection
            Divider()
            appSection
        }
        .padding(14)
        .frame(width: 300)
        .toggleStyle(.switch)
        .controlSize(.small)
        .onAppear {
            controller.refreshPermissions()
            syncDPIIndex()
        }
        .onChange(of: controller.currentDPI) { syncDPIIndex() }
        .onChange(of: controller.supportedDPIs) { syncDPIIndex() }
    }

    // MARK: Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "computermouse.fill")
                    .foregroundStyle(.secondary)
                    .frame(width: iconWidth)
                Text(controller.deviceName ?? SupportedDevices.mxMaster3S.name)
                    .font(.headline)
                Spacer()
                statusBadge
            }
            if let battery = controller.battery {
                Label(batteryText(battery), systemImage: batterySymbol(battery))
                    .font(.callout)
                    .foregroundStyle(battery.percentage <= settings.lowBatteryThreshold && !battery.charging.isCharging ? .red : .secondary)
            }
            if let error = controller.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }
        }
    }

    private var statusBadge: some View {
        let (text, color): (String, Color) = switch controller.connection {
        case .connected: ("Connected", .green)
        case .searching: ("Searching…", .secondary)
        case .notFound: ("Not found", .secondary)
        case .permissionRequired: ("No access", .orange)
        case .failed: ("Error", .red)
        }
        return HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text).font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var permissionWarnings: some View {
        if !controller.inputMonitoringGranted || controller.connection == .permissionRequired {
            permissionRow(.inputMonitoring, detail: "Needed to talk to the mouse.")
        }
        if !controller.accessibilityGranted && (settings.backForwardEnabled || controller.scrollFallbackActive) {
            permissionRow(.accessibility, detail: "Needed for Back/Forward and Mission Control.")
        }
        if controller.needsRelaunch {
            HStack {
                Text("Relaunch to apply Input Monitoring access.")
                    .font(.caption)
                Spacer()
                Button("Relaunch") { controller.relaunch() }
            }
        }
        if case .failed(let message) = controller.connection {
            Text(message).font(.caption).foregroundStyle(.red)
        }
    }

    private func permissionRow(_ permission: Permission, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .frame(width: iconWidth)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(permission.title) required").font(.callout)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Open…") { permission.openSettings() }
        }
    }

    private var wheelSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            dropdown("Scroll direction", selection: Binding(
                get: { settings.mouseScrollDirection },
                set: { controller.setScrollDirection($0) }
            )) {
                Text("Natural").tag(SettingsStore.ScrollDirection.natural)
                Text("Standard").tag(SettingsStore.ScrollDirection.standard)
            }
            if controller.scrollFallbackActive {
                Text("Using event-tap fallback for scroll inversion.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            dropdown("Thumb wheel", selection: Binding(
                get: { settings.thumbWheelInverted },
                set: { controller.setThumbWheelInverted($0) }
            )) {
                Text("Normal").tag(false)
                Text("Inverted").tag(true)
            }
        }
    }

    private var pointerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Pointer speed")
                Spacer()
                Text(dpiLabel)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            let dpis = controller.supportedDPIs
            // Snap by rounding rather than `step:`, which on macOS draws a tick per step;
            // with ~150 DPI values those merge into a second line under the track.
            Slider(
                value: Binding(get: { dpiIndex }, set: { dpiIndex = $0.rounded() }),
                in: 0...Double(max(dpis.count - 1, 1)),
                onEditingChanged: { editing in
                    draggingDPI = editing
                    // Apply once on release instead of on every step of the drag.
                    if !editing, dpis.indices.contains(Int(dpiIndex)) {
                        controller.setDPI(dpis[Int(dpiIndex)])
                    }
                }
            )
            .disabled(dpis.count < 2)
        }
    }

    private var buttonsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            toggleRow(
                "Back/Forward buttons",
                detail: "Sends ⌘[ and ⌘] (works in Safari)",
                isOn: Binding(get: { settings.backForwardEnabled }, set: { controller.setBackForward($0) })
            )
            toggleRow(
                "Thumb button → Mission Control",
                detail: controller.gestureButtonAvailable == false ? "Not available on this device" : nil,
                isOn: Binding(get: { settings.gestureMissionControl }, set: { controller.setGestureMissionControl($0) })
            )
        }
    }

    private var appSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            toggleRow(
                "Battery in menu bar",
                isOn: Binding(get: { settings.showBatteryInMenuBar }, set: { controller.setShowBatteryInMenuBar($0) })
            )
            dropdown("Low battery warning", selection: Binding(
                get: { settings.lowBatteryThreshold },
                set: { controller.setLowBatteryThreshold($0) }
            )) {
                ForEach(SettingsStore.lowBatteryThresholdOptions, id: \.self) { level in
                    Text(level == 0 ? "None" : "\(level)%").tag(level)
                }
            }
            toggleRow(
                "Launch at login",
                detail: controller.launchAtLoginNeedsApproval ? "Approve in System Settings › Login Items" : nil,
                isOn: Binding(get: { controller.launchAtLogin }, set: { controller.setLaunchAtLogin($0) })
            )
            HStack {
                if controller.launchAtLoginNeedsApproval {
                    Button("Login Items…") { LoginItem.openSettings() }
                }
                Spacer()
                Button("Quit Mouse Control") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
        }
    }

    // MARK: Helpers

    /// A settings row: title (and optional detail) on the leading edge, control pinned to the trailing edge.
    private func row(_ title: String, detail: String? = nil, @ViewBuilder control: () -> some View) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                if let detail {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            control()
        }
    }

    /// Switch toggles render their own label, so hide it and use `row` to keep
    /// every title in the same font and every switch on the same trailing edge.
    private func toggleRow(_ title: String, detail: String? = nil, isOn: Binding<Bool>) -> some View {
        row(title, detail: detail) {
            Toggle(title, isOn: isOn)
                .labelsHidden()
        }
    }

    /// A pop-up menu picker with a shared fixed width so every dropdown lines up
    /// on the trailing edge regardless of its option text.
    private func dropdown<Value: Hashable>(
        _ title: String,
        selection: Binding<Value>,
        @ViewBuilder options: () -> some View
    ) -> some View {
        row(title) {
            Picker(title, selection: selection, content: options)
                .pickerStyle(.menu)
                .labelsHidden()
                // Menu pickers hug their content by default; let them fill the
                // shared width so every dropdown has the same edges.
                .buttonSizing(.flexible)
                .frame(width: dropdownWidth)
        }
    }


    private var dpiLabel: String {
        let dpis = controller.supportedDPIs
        if draggingDPI, dpis.indices.contains(Int(dpiIndex)) { return "\(dpis[Int(dpiIndex)]) DPI" }
        if let dpi = controller.currentDPI { return "\(dpi) DPI" }
        return "—"
    }

    private func syncDPIIndex() {
        guard !draggingDPI else { return }
        let dpis = controller.supportedDPIs
        guard let target = controller.currentDPI ?? settings.dpi,
              let snapped = AdjustableDPIFeature.snap(target, to: dpis),
              let index = dpis.firstIndex(of: snapped) else { return }
        dpiIndex = Double(index)
    }

    private func batteryText(_ battery: BatteryStatus) -> String {
        let state = switch battery.charging {
        case .charging, .chargingSlow: "Charging"
        case .full: "Charged"
        case .error: "Charging error"
        case .discharging: battery.externalPower ? "Plugged in" : "On battery"
        }
        return "\(battery.percentage)% — \(state)"
    }

    private func batterySymbol(_ battery: BatteryStatus) -> String {
        if battery.charging.isCharging { return "battery.100percent.bolt" }
        return switch battery.percentage {
        case ..<13: "battery.0percent"
        case ..<38: "battery.25percent"
        case ..<63: "battery.50percent"
        case ..<88: "battery.75percent"
        default: "battery.100percent"
        }
    }
}
