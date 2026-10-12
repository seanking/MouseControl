import AppKit
import Carbon.HIToolbox
import MouseControlKit
import os
import ServiceManagement

enum SystemActions {
    private static let logger = Logger(subsystem: Log.subsystem, category: "system")

    /// Opens Mission Control. Falls back to a synthesized Ctrl+↑ if the app can't be launched.
    static func openMissionControl() {
        let url = URL(fileURLWithPath: "/System/Applications/Mission Control.app")
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            guard let error else { return }
            logger.error("Mission Control.app launch failed: \(error.localizedDescription, privacy: .public); using Ctrl+Up")
            postKeystroke(keyCode: CGKeyCode(kVK_UpArrow), flags: [.maskControl, .maskSecondaryFn, .maskNumericPad])
        }
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
