import AppKit
import Carbon.HIToolbox
import MouseControlKit
import os
import ServiceManagement

enum SystemActions {
    private static let logger = Logger(subsystem: Log.subsystem, category: "system")

    /// Modifier flags real arrow-key events carry; some system shortcuts don't match without them.
    private static let arrowKeyFlags: CGEventFlags = [.maskSecondaryFn, .maskNumericPad]

    /// Runs a thumb button action. Everything except Mission Control relies on the default
    /// system shortcuts (System Settings › Keyboard › Keyboard Shortcuts).
    static func perform(_ action: SettingsStore.ThumbButtonAction) {
        switch action {
        case .none:
            break
        case .missionControl:
            openMissionControl()
        case .appExpose:
            postKeystroke(keyCode: CGKeyCode(kVK_DownArrow), flags: arrowKeyFlags.union(.maskControl))
        case .showDesktop:
            postKeystroke(keyCode: CGKeyCode(kVK_F11), flags: .maskSecondaryFn)
        case .spotlight:
            postKeystroke(keyCode: CGKeyCode(kVK_Space), flags: .maskCommand)
        case .notificationCenter:
            toggleNotificationCenter()
        }
    }

    /// Moves to the adjacent Space with the default ⌃← / ⌃→ shortcuts.
    static func switchSpace(toNext next: Bool) {
        let key = next ? kVK_RightArrow : kVK_LeftArrow
        postKeystroke(keyCode: CGKeyCode(key), flags: arrowKeyFlags.union(.maskControl))
    }

    /// Opens Mission Control. Falls back to a synthesized Ctrl+↑ if the app can't be launched.
    static func openMissionControl() {
        let url = URL(fileURLWithPath: "/System/Applications/Mission Control.app")
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            guard let error else { return }
            logger.error("Mission Control.app launch failed: \(error.localizedDescription, privacy: .public); using Ctrl+Up")
            postKeystroke(keyCode: CGKeyCode(kVK_UpArrow), flags: arrowKeyFlags.union(.maskControl))
        }
    }

    /// Notification Center has no default shortcut, so press the menu bar clock (owned by
    /// Control Center) through the Accessibility API, which is what a click on it does.
    static func toggleNotificationCenter() {
        guard let controlCenter = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.controlcenter").first else {
            logger.error("Control Center isn't running; can't open Notification Center")
            return
        }
        let app = AXUIElementCreateApplication(controlCenter.processIdentifier)
        guard let menuBar = element(app, kAXExtrasMenuBarAttribute),
              let items = copyAttribute(menuBar, kAXChildrenAttribute) as? [AXUIElement],
              let clock = items.first(where: { copyAttribute($0, kAXIdentifierAttribute) as? String == "com.apple.menuextra.clock" })
        else {
            logger.error("Menu bar clock not found; can't open Notification Center")
            return
        }
        let result = AXUIElementPerformAction(clock, kAXPressAction as CFString)
        if result != .success {
            logger.error("Pressing the menu bar clock failed: \(result.rawValue)")
        }
    }

    private static func copyAttribute(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    private static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let value = copyAttribute(element, attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        // The type ID check above makes this cast safe.
        return (value as! AXUIElement)
    }

    static func postKeystroke(keyCode: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .privateState)
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: down) else { continue }
            event.flags = flags
            event.post(tap: .cghidEventTap)
        }
    }
}

enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }
    static var needsApproval: Bool { SMAppService.mainApp.status == .requiresApproval }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    static func openSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
