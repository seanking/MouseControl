import Foundation
import IOKit
import IOKit.hid

extension HIDDeviceInfo {
    /// Reads the identity properties an IOHIDDevice publishes in the IORegistry.
    init(service: io_service_t) {
        var id: UInt64 = 0
        IORegistryEntryGetRegistryEntryID(service, &id)
        self.init(
            registryID: id,
            vendorID: HIDRegistry.property(service, kIOHIDVendorIDKey) ?? 0,
            productID: HIDRegistry.property(service, kIOHIDProductIDKey) ?? 0,
            locationID: HIDRegistry.property(service, kIOHIDLocationIDKey) ?? 0,
            product: HIDRegistry.property(service, kIOHIDProductKey),
            transport: HIDRegistry.property(service, kIOHIDTransportKey)
        )
    }
}

/// Reads HID devices' IORegistry properties. Needs no permission and never opens a device.
public enum HIDRegistry {
    static func property<T>(_ entry: io_registry_entry_t, _ key: String) -> T? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? T
    }

    /// The charge that macOS reads from an Apple Bluetooth peripheral and publishes on one of its
    /// HID event services. Matched by location so two identical mice don't swap batteries.
    public static func batteryPercent(of device: HIDDeviceInfo) -> Int? {
        let matching = IOServiceMatching("IOHIDEventService") as NSMutableDictionary
        matching.addEntries(from: [
            kIOHIDVendorIDKey: device.vendorID,
            kIOHIDProductIDKey: device.productID,
            kIOHIDLocationIDKey: device.locationID,
        ])
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == kIOReturnSuccess else { return nil }
        defer { IOObjectRelease(iterator) }
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            if let percent: Int = property(service, "BatteryPercent") { return percent }
        }
        return nil
    }
}
