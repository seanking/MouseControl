import Foundation

/// Static knowledge about a supported device. Add entries here to support more mice.
public struct DeviceProfile: Sendable, Equatable {
    public let name: String
    /// USB product IDs the device reports when connected directly over Bluetooth.
    public let bluetoothProductIDs: Set<Int>
    /// Control IDs that identify the gesture/thumb button, in preference order. The device's own
    /// control list (0x1B04) is consulted to confirm one exists and is divertable before diverting it.
    public let gestureButtonCIDs: [UInt16]
}

public enum SupportedDevices {
    public static let logitechVendorID = 0x046D

    /// HID++ collection on Logitech BLE devices (long reports only).
    public static let bleHIDPPUsagePage = 0xFF43
    public static let bleHIDPPUsage = 0x0202

    public static let mxMaster3S = DeviceProfile(
        name: "MX Master 3S",
        bluetoothProductIDs: [0xB034],
        gestureButtonCIDs: [0x00C3]  // "Mouse Gesture Button"
    )

    public static let all: [DeviceProfile] = [mxMaster3S]

    public static func profile(vendorID: Int, productID: Int, productName: String?) -> DeviceProfile? {
        guard vendorID == logitechVendorID else { return nil }
        if let match = all.first(where: { $0.bluetoothProductIDs.contains(productID) }) { return match }
        // Unknown PID variant (e.g. a business SKU) that still names itself.
        guard let productName else { return nil }
        return all.first { productName.localizedCaseInsensitiveContains($0.name) }
    }

    /// Picks the gesture button from the device's control list.
    public static func gestureButton(in controls: [ReprogControlsFeature.Control], profile: DeviceProfile) -> UInt16? {
        for cid in profile.gestureButtonCIDs {
            if let control = controls.first(where: { $0.cid == cid }), control.isDivertable { return cid }
        }
        return nil
    }
}
