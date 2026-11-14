import Foundation
import IOKit
import IOKit.hid

/// Watches the IORegistry for HID devices without opening them, so it needs no permission.
/// Callbacks run on a private serial queue (never the main thread).
public final class DeviceMonitor: @unchecked Sendable {
    /// Called on the monitor's queue, including once for each device already present at `start()`.
    public var onMatched: (@Sendable (HIDDeviceInfo) -> Void)?
    public var onRemoved: (@Sendable (HIDDeviceInfo) -> Void)?

    private let queue = DispatchQueue(label: "MouseControl.monitor", qos: .utility)
    private let matching: [[String: Int]]
    private var port: IONotificationPortRef?
    private var iterators: [io_iterator_t] = []
    /// Matching devices currently present, by registry ID. A terminated entry may no longer
    /// publish its properties, so removal reports what was read on match.
    private var present: [UInt64: HIDDeviceInfo] = [:]

    public init(matching: [[String: Int]]) {
        self.matching = matching
    }

    /// Matches the pointer collection of every known Magic Mouse; each mouse has one.
    public static func magicMouse() -> DeviceMonitor {
        DeviceMonitor(matching: SupportedDevices.magicMouseIDs.map { id in
            [
                kIOHIDVendorIDKey: id.vendorID,
                kIOHIDProductIDKey: id.productID,
                kIOHIDPrimaryUsagePageKey: SupportedDevices.genericDesktopUsagePage,
                kIOHIDPrimaryUsageKey: SupportedDevices.mouseUsage,
            ]
        })
    }

    public func start() {
        queue.sync {
            guard port == nil, let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
            IONotificationPortSetDispatchQueue(port, queue)
            self.port = port

            let context = Unmanaged.passUnretained(self).toOpaque()
            for properties in matching {
                for added in [true, false] {
                    let dictionary = IOServiceMatching(kIOHIDDeviceKey) as NSMutableDictionary
                    dictionary.addEntries(from: properties)
                    var iterator: io_iterator_t = 0
                    let callback: IOServiceMatchingCallback = added
                        ? { context, iterator in Unmanaged<DeviceMonitor>.fromOpaque(context!).takeUnretainedValue().drainMatched(iterator) }
                        : { context, iterator in Unmanaged<DeviceMonitor>.fromOpaque(context!).takeUnretainedValue().drainRemoved(iterator) }
                    let result = IOServiceAddMatchingNotification(
                        port, added ? kIOFirstMatchNotification : kIOTerminatedNotification,
                        dictionary, callback, context, &iterator
                    )
                    guard result == kIOReturnSuccess else {
                        Log.transport.error("Device notification failed: \(String(format: "0x%08X", UInt32(bitPattern: result)), privacy: .public)")
                        continue
                    }
                    iterators.append(iterator)
                    // Walking the iterator reports devices already present and arms the notification.
                    added ? drainMatched(iterator) : drainRemoved(iterator)
                }
            }
        }
    }

    public func stop() {
        queue.sync {
            iterators.forEach { IOObjectRelease($0) }
            iterators.removeAll()
            if let port { IONotificationPortDestroy(port) }
            port = nil
            present.removeAll()
        }
    }

    // MARK: - Callbacks (monitor queue)

    private func drainMatched(_ iterator: io_iterator_t) {
        while case let service = IOIteratorNext(iterator), service != 0 {
            let info = HIDDeviceInfo(service: service)
            IOObjectRelease(service)
            guard present.updateValue(info, forKey: info.registryID) == nil else { continue }
            Log.transport.info("Monitor matched \(info.product ?? "?", privacy: .public) pid=\(String(format: "0x%04X", info.productID), privacy: .public)")
            onMatched?(info)
        }
    }

    private func drainRemoved(_ iterator: io_iterator_t) {
        while case let service = IOIteratorNext(iterator), service != 0 {
            var id: UInt64 = 0
            IORegistryEntryGetRegistryEntryID(service, &id)
            IOObjectRelease(service)
            guard let info = present.removeValue(forKey: id) else { continue }
            Log.transport.info("Monitor removed \(info.product ?? "?", privacy: .public)")
            onRemoved?(info)
        }
    }
}
