import MouseControlKit
import SwiftUI

struct MenuBarLabel: View {
    let controller: DeviceController

    var body: some View {
        let connected = controller.connectedDevices
        let symbol = connected.isEmpty ? "computermouse" : "computermouse.fill"
        if controller.settings.showBatteryInMenuBar, let battery = connected.lazy.compactMap(\.battery).first {
            HStack(spacing: 2) {
                Image(systemName: symbol)
                Text("\(battery.percentage)%")
            }
        } else {
            Image(systemName: symbol)
        }
    }
}

/// One section per connected mouse with only the options that mouse supports,
/// followed by the app-wide options.
struct MenuContentView: View {
    let controller: DeviceController

    private var settings: SettingsStore { controller.settings }
    /// "Mouse Control", or "Mouse Control-Dev" for Debug builds.
    private var appName: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Mouse Control" }
    private var logitech: LogitechMouse { controller.logitech }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if hasWarnings {
                warnings
                Divider()
            }
            if logitech.isConnected {
                LogitechMouseSection(mouse: logitech, settings: settings)
                Divider()
            }
            if controller.magicMouse.isConnected {
                MagicMouseSection(mouse: controller.magicMouse, settings: settings)
                Divider()
            }
            if controller.connectedDevices.isEmpty {
                noMouseHeader
            } else {
                batterySection
            }
            Divider()
            appSection
        }
        .padding(14)
        .frame(width: 300)
        .toggleStyle(.switch)
        .controlSize(.small)
        .onAppear { controller.refreshPermissions() }
    }

    // MARK: Sections

    private var noMouseHeader: some View {
        let (text, color): (String, Color) = switch logitech.connection {
        case .searching: ("Searching…", .secondary)
        case .connected, .notFound: ("Not found", .secondary)
        case .permissionRequired: ("No access", .orange)
        case .failed: ("Error", .red)
        }
        return HStack {
            Image(systemName: "computermouse")
                .foregroundStyle(.secondary)
                .frame(width: MenuMetrics.iconWidth)
            Text("No mouse connected")
                .font(.headline)
            Spacer()
            StatusBadge(text: text, color: color)
        }
    }

    /// Input Monitoring is needed to find a Logitech mouse at all, so it's asked for even while none
    /// is connected. Accessibility only matters for options the Logitech section shows.
    private var needsInputMonitoring: Bool {
        !controller.inputMonitoringGranted || logitech.connection == .permissionRequired
    }

    private var needsAccessibility: Bool {
        logitech.isConnected && !controller.accessibilityGranted
            && (settings.backForwardEnabled || logitech.scrollFallbackActive || settings.thumbButtonNeedsAccessibility)
    }

    private var transportFailure: String? {
        if case .failed(let message) = logitech.connection { message } else { nil }
    }

    private var hasWarnings: Bool {
        needsInputMonitoring || needsAccessibility || logitech.needsRelaunch || transportFailure != nil
    }

    @ViewBuilder
    private var warnings: some View {
        if needsInputMonitoring {
            permissionRow(.inputMonitoring, detail: "Needed to talk to Logitech mice.")
        }
        if needsAccessibility {
            permissionRow(.accessibility, detail: "Needed for Back/Forward and the thumb button.")
        }
        if logitech.needsRelaunch {
            HStack {
                Text("Relaunch to apply Input Monitoring access.")
                    .font(.caption)
                Spacer()
                Button("Relaunch") { controller.relaunch() }
            }
        }
        if let transportFailure {
            Text(transportFailure).font(.caption).foregroundStyle(.red)
        }
    }

    private func permissionRow(_ permission: Permission, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .frame(width: MenuMetrics.iconWidth)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(permission.title) required").font(.callout)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Open…") { permission.openSettings() }
        }
    }

    /// Every supported mouse reports its battery, so these apply whenever one is connected.
    private var batterySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingToggle(
                title: "Battery in menu bar",
                isOn: Binding(get: { settings.showBatteryInMenuBar }, set: { controller.setShowBatteryInMenuBar($0) })
            )
            SettingDropdown(title: "Low battery warning", selection: Binding(
                get: { settings.lowBatteryThreshold },
                set: { controller.setLowBatteryThreshold($0) }
            )) {
                ForEach(SettingsStore.lowBatteryThresholdOptions, id: \.self) { level in
                    Text(level == 0 ? "None" : "\(level)%").tag(level)
                }
            }
        }
    }

    private var appSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingToggle(
                title: "Launch at login",
                detail: controller.launchAtLoginNeedsApproval ? "Approve in System Settings › Login Items" : nil,
                isOn: Binding(get: { controller.launchAtLogin }, set: { controller.setLaunchAtLogin($0) })
            )
            if let error = controller.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }
            HStack {
                if controller.launchAtLoginNeedsApproval {
                    Button("Login Items…") { LoginItem.openSettings() }
                }
                Spacer()
                Button("Quit \(appName)") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
        }
    }
}
