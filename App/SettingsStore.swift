import Foundation
import Observation

/// User settings, persisted in UserDefaults and re-applied to the device on every connect.
@MainActor @Observable
final class SettingsStore {
    enum ScrollDirection: String, CaseIterable {
        case natural, standard
    }

    /// What a press of the thumb (gesture) button does. Raw values are persisted.
    enum ThumbButtonAction: String, CaseIterable {
        case none, missionControl, appExpose, showDesktop, spotlight, notificationCenter

        var title: String {
            switch self {
            case .none: "None"
            case .missionControl: "Mission Control"
            case .appExpose: "App Exposé"
            case .showDesktop: "Show Desktop"
            case .spotlight: "Spotlight"
            case .notificationCenter: "Notification Center"
            }
        }

        /// The system shortcut the action sends, if any; it only works while enabled in System Settings.
        var systemShortcut: String? {
            switch self {
            case .appExpose: "⌃↓"
            case .showDesktop: "F11"
            case .spotlight: "⌘Space"
            case .none, .missionControl, .notificationCenter: nil
            }
        }

        /// Posting keystrokes and pressing menu bar items both need Accessibility. Mission Control
        /// launches an app, but its Ctrl+↑ fallback still posts a keystroke.
        var needsAccessibility: Bool { self != .none }
    }

    private enum Key {
        static let mouseScrollDirection = "mouseScrollDirection"
        static let thumbWheelInverted = "thumbWheelInverted"
        static let dpi = "dpi"
        static let magicMouseTrackingSpeed = "magicMouseTrackingSpeed"
        static let backForwardEnabled = "backForwardEnabled"
        /// Legacy on/off flag, read once to migrate into `thumbButtonAction`.
        static let gestureMissionControl = "gestureMissionControl"
        static let thumbButtonAction = "thumbButtonAction"
        static let thumbButtonSwipeSpaces = "thumbButtonSwipeSpaces"
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
    /// System tracking speed to apply while a Magic Mouse is connected; nil leaves the system's alone.
    var magicMouseTrackingSpeed: Double? {
        didSet { defaults.set(magicMouseTrackingSpeed, forKey: Key.magicMouseTrackingSpeed) }
    }
    var backForwardEnabled: Bool {
        didSet { defaults.set(backForwardEnabled, forKey: Key.backForwardEnabled) }
    }
    var thumbButtonAction: ThumbButtonAction {
        didSet { defaults.set(thumbButtonAction.rawValue, forKey: Key.thumbButtonAction) }
    }
    /// Hold the thumb button and drag left/right to switch Spaces; a click still runs `thumbButtonAction`.
    var thumbButtonSwipeSpaces: Bool {
        didSet { defaults.set(thumbButtonSwipeSpaces, forKey: Key.thumbButtonSwipeSpaces) }
    }
    /// Swiping posts ⌃← / ⌃→ and every action except None posts events, so both need Accessibility.
    var thumbButtonNeedsAccessibility: Bool {
        thumbButtonSwipeSpaces || thumbButtonAction.needsAccessibility
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
            Key.thumbButtonSwipeSpaces: false,
            Key.showBatteryInMenuBar: false,
            Key.lowBatteryWarning: true,
            Key.didInitialLoginItemSetup: false,
        ])
        mouseScrollDirection = ScrollDirection(rawValue: defaults.string(forKey: Key.mouseScrollDirection) ?? "") ?? .standard
        thumbWheelInverted = defaults.bool(forKey: Key.thumbWheelInverted)
        dpi = defaults.object(forKey: Key.dpi) as? Int
        magicMouseTrackingSpeed = defaults.object(forKey: Key.magicMouseTrackingSpeed) as? Double
        backForwardEnabled = defaults.bool(forKey: Key.backForwardEnabled)
        if let action = defaults.string(forKey: Key.thumbButtonAction).flatMap(ThumbButtonAction.init(rawValue:)) {
            thumbButtonAction = action
        } else {
            // Migrate the old on/off setting: on was Mission Control.
            thumbButtonAction = defaults.bool(forKey: Key.gestureMissionControl) ? .missionControl : .none
        }
        thumbButtonSwipeSpaces = defaults.bool(forKey: Key.thumbButtonSwipeSpaces)
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
