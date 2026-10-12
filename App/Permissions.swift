import AppKit
import ApplicationServices
import IOKit.hid

enum Permission {
    case inputMonitoring, accessibility

    var title: String {
        switch self {
        case .inputMonitoring: "Input Monitoring"
        case .accessibility: "Accessibility"
        }
    }

    var isGranted: Bool {
        switch self {
        case .inputMonitoring: IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
        case .accessibility: AXIsProcessTrusted()
        }
    }

    /// Adds the app to the System Settings list (and prompts) if the user hasn't decided yet.
    func requestIfUndetermined() {
        switch self {
        case .inputMonitoring:
            if IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeUnknown {
                _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
            }
        case .accessibility:
            if !AXIsProcessTrusted() {
                let key = "AXTrustedCheckOptionPrompt" as CFString
                _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
            }
        }
    }

    func openSettings() {
        let anchor = switch self {
        case .inputMonitoring: "Privacy_ListenEvent"
        case .accessibility: "Privacy_Accessibility"
        }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }
}
