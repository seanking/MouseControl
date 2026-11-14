import MouseControlKit
import SwiftUI

/// Layout constants shared by every menu section so rows line up across sections.
enum MenuMetrics {
    /// Shared width for leading header icons so the text beside them lines up.
    static let iconWidth: CGFloat = 18
    /// Shared width for dropdowns so they match each other exactly.
    static let dropdownWidth: CGFloat = 110
}

/// A settings row: title (and optional detail) on the leading edge, control pinned to the trailing edge.
struct SettingRow<Control: View>: View {
    let title: String
    var detail: String?
    @ViewBuilder let control: Control

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                if let detail {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            control
        }
    }
}

/// Switch toggles render their own label, so hide it and use `SettingRow` to keep
/// every title in the same font and every switch on the same trailing edge.
struct SettingToggle: View {
    let title: String
    var detail: String?
    @Binding var isOn: Bool

    var body: some View {
        SettingRow(title: title, detail: detail) {
            Toggle(title, isOn: $isOn)
                .labelsHidden()
        }
    }
}

/// A pop-up menu picker with a shared fixed width so every dropdown lines up
/// on the trailing edge regardless of its option text.
struct SettingDropdown<Value: Hashable, Options: View>: View {
    let title: String
    var detail: String?
    @Binding var selection: Value
    @ViewBuilder let options: Options

    var body: some View {
        SettingRow(title: title, detail: detail) {
            Picker(title, selection: $selection) { options }
                .pickerStyle(.menu)
                .labelsHidden()
                // Menu pickers hug their content by default; let them fill the
                // shared width so every dropdown has the same edges.
                .buttonSizing(.flexible)
                .frame(width: MenuMetrics.dropdownWidth)
        }
    }
}

/// A titled slider with its current value on the trailing edge. Values are snapped by rounding
/// rather than `step:`, which on macOS draws a tick per step; with many steps those merge into
/// a second line under the track.
struct SettingSlider: View {
    let title: String
    let valueLabel: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let snap: (Double) -> Double
    var onEditingChanged: (Bool) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(valueLabel)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(
                value: Binding(get: { value }, set: { value = snap($0) }),
                in: range,
                onEditingChanged: onEditingChanged
            )
        }
    }
}

/// The name, connection badge, and battery of one connected mouse.
struct DeviceHeader: View {
    let name: String
    let battery: BatteryStatus?
    let lowBatteryThreshold: Int
    var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "computermouse.fill")
                    .foregroundStyle(.secondary)
                    .frame(width: MenuMetrics.iconWidth)
                Text(name)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                StatusBadge(text: "Connected", color: .green)
            }
            if let battery {
                Label(batteryText(battery), systemImage: batterySymbol(battery))
                    .font(.callout)
                    .foregroundStyle(battery.percentage <= lowBatteryThreshold && !battery.charging.isCharging ? .red : .secondary)
            }
            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }
        }
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

struct StatusBadge: View {
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text).font(.caption).foregroundStyle(.secondary)
        }
    }
}
