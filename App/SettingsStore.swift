import Foundation
import Observation

/// User settings, persisted in UserDefaults and re-applied to the device on every connect.
@MainActor @Observable
final class SettingsStore {
    enum ScrollDirection: String, CaseIterable {
        case natural, standard
    }

    private enum Key {
        static let mouseScrollDirection = "mouseScrollDirection"
        static let thumbWheelInverted = "thumbWheelInverted"
        static let dpi = "dpi"
        static let backForwardEnabled = "backForwardEnabled"
        static let gestureMissionControl = "gestureMissionControl"
        static let showBatteryInMenuBar = "showBatteryInMenuBar"
        /// Legacy on/off flag, read once to migrate into `lowBatteryThreshold`.
        static let lowBatteryWarning = "lowBatteryWarning"
        static let lowBatteryThreshold = "lowBatteryThreshold"
        static let didInitialLoginItemSetup = "didInitialLoginItemSetup"
    }

    @ObservationIgnored private let defaults: UserDefaults

    var mouseScrollDirection: ScrollDirection {
        didSet { defaults.set(mouseScrollDirection.rawValue, forKey: Key.mouseScrollDirection) }
    }
    var thumbWheelInverted: Bool {
        didSet { defaults.set(thumbWheelInverted, forKey: Key.thumbWheelInverted) }
    }
    /// nil until the user picks a value; the device's own DPI is left alone until then.
    var dpi: Int? {
        didSet { defaults.set(dpi, forKey: Key.dpi) }
    }
    var backForwardEnabled: Bool {
        didSet { defaults.set(backForwardEnabled, forKey: Key.backForwardEnabled) }
    }
    var gestureMissionControl: Bool {
        didSet { defaults.set(gestureMissionControl, forKey: Key.gestureMissionControl) }
    }
    var showBatteryInMenuBar: Bool {
        didSet { defaults.set(showBatteryInMenuBar, forKey: Key.showBatteryInMenuBar) }
    }
    /// Battery percentage at which to warn; 0 disables the warning.
    var lowBatteryThreshold: Int {
        didSet { defaults.set(lowBatteryThreshold, forKey: Key.lowBatteryThreshold) }
    }
    static let lowBatteryThresholdOptions = [0, 5, 10, 15, 20]
    var didInitialLoginItemSetup: Bool {
        didSet { defaults.set(didInitialLoginItemSetup, forKey: Key.didInitialLoginItemSetup) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.mouseScrollDirection: ScrollDirection.standard.rawValue,
            Key.thumbWheelInverted: false,
            Key.backForwardEnabled: true,
            Key.gestureMissionControl: true,
            Key.showBatteryInMenuBar: false,
            Key.lowBatteryWarning: true,
            Key.didInitialLoginItemSetup: false,
        ])
        mouseScrollDirection = ScrollDirection(rawValue: defaults.string(forKey: Key.mouseScrollDirection) ?? "") ?? .standard
        thumbWheelInverted = defaults.bool(forKey: Key.thumbWheelInverted)
        dpi = defaults.object(forKey: Key.dpi) as? Int
        backForwardEnabled = defaults.bool(forKey: Key.backForwardEnabled)
        gestureMissionControl = defaults.bool(forKey: Key.gestureMissionControl)
        showBatteryInMenuBar = defaults.bool(forKey: Key.showBatteryInMenuBar)
        if let threshold = defaults.object(forKey: Key.lowBatteryThreshold) as? Int {
            lowBatteryThreshold = threshold
        } else {
            // Migrate the old on/off setting: on was a fixed 10%.
            lowBatteryThreshold = defaults.bool(forKey: Key.lowBatteryWarning) ? 10 : 0
        }
        didInitialLoginItemSetup = defaults.bool(forKey: Key.didInitialLoginItemSetup)
    }

    /// macOS's single "natural scrolling" preference (shared by trackpad and mouse).
    static var systemNaturalScrolling: Bool {
        UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?["com.apple.swipescrolldirection"] as? Bool ?? true
    }
}
