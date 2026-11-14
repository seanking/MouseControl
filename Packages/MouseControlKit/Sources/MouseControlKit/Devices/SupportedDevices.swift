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

    /// HID++ collection on Logitech USB receivers (short and long reports).
    public static let receiverHIDPPUsagePage = 0xFF00
    public static let receiverHIDPPUsage = 0x0002
    /// Logi Bolt receiver.
    public static let receiverProductIDs: Set<Int> = [0xC548]

    public static func isReceiver(vendorID: Int, productID: Int) -> Bool {
        vendorID == logitechVendorID && receiverProductIDs.contains(productID)
    }

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
        return profile(named: productName)
    }

    /// Matches by the name a device reports, e.g. via Device Name (0x0005) behind a receiver.
    public static func profile(named name: String) -> DeviceProfile? {
        all.first { name.localizedCaseInsensitiveContains($0.name) }
    }

    // MARK: Magic Mouse

    /// Apple's Bluetooth vendor ID; the same mice report the USB vendor ID when connected by cable.
    public static let appleBluetoothVendorID = 0x004C
    public static let appleUSBVendorID = 0x05AC
    /// Magic Mouse (0x030D), Magic Mouse 2 (0x0269), Magic Mouse with USB-C (0x0323).
    public static let magicMouseProductIDs = [0x030D, 0x0269, 0x0323]
    public static let magicMouseIDs: [(vendorID: Int, productID: Int)] =
        [appleBluetoothVendorID, appleUSBVendorID].flatMap { vendor in magicMouseProductIDs.map { (vendor, $0) } }

    /// Generic Desktop › Mouse: the pointer collection, one per physical mouse.
    public static let genericDesktopUsagePage = 0x01
    public static let mouseUsage = 0x02

    /// Picks the gesture button from the device's control list.
    public static func gestureButton(in controls: [ReprogControlsFeature.Control], profile: DeviceProfile) -> UInt16? {
        for cid in profile.gestureButtonCIDs {
            if let control = controls.first(where: { $0.cid == cid }), control.isDivertable { return cid }
        }
        return nil
    }
}
