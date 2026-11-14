import Foundation
import IOKit
import IOKit.hid

/// Identity of a matched HID device.
public struct HIDDeviceInfo: Sendable, Hashable {
    /// IORegistry entry ID; stable for the lifetime of one connection.
    public let registryID: UInt64
    public let vendorID: Int
    public let productID: Int
    public let locationID: Int
    public let product: String?
    public let transport: String?
}

/// One open HID device. Input reports arrive on the transport's queue.
public final class HIDConnection: @unchecked Sendable {
    public let info: HIDDeviceInfo
    fileprivate let device: IOHIDDevice
    // Only touched on the transport queue.
    fileprivate var inputHandler: (@Sendable ([UInt8]) -> Void)?

    fileprivate init(device: IOHIDDevice, info: HIDDeviceInfo) {
        self.device = device
        self.info = info
    }

    /// Sends an output report. `bytes[0]` must be the report ID.
    public func send(_ bytes: [UInt8]) throws {
        guard let reportID = bytes.first else { return }
        let result = bytes.withUnsafeBufferPointer { buffer in
            IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, CFIndex(reportID), buffer.baseAddress!, buffer.count)
        }
        guard result == kIOReturnSuccess else { throw HIDPPError.sendFailed(result) }
    }

    fileprivate func deliver(reportID: UInt32, report: UnsafeMutablePointer<UInt8>, length: Int) {
        // Mouse movement reports arrive here too; reject anything that isn't HID++ before copying.
        guard reportID == HIDPP.shortReportID || reportID == HIDPP.longReportID, let inputHandler else { return }
        var bytes = Array(UnsafeBufferPointer(start: report, count: length))
        if bytes.first != UInt8(reportID) || (length != HIDPP.longReportLength && length != HIDPP.shortReportLength) {
            bytes.insert(UInt8(reportID), at: 0)
        }
        inputHandler(bytes)
    }
}

/// IOHIDManager wrapper. All IOKit callbacks run on a private serial queue (never the main thread).
public final class HIDTransport: @unchecked Sendable {
    public enum StartResult: Sendable, Equatable {
        case ok
        case notPermitted
        case failed(Int32)
    }

    /// Called on the transport queue. Set the connection's input handler synchronously here.
    public var onMatched: (@Sendable (HIDConnection) -> Void)?
    public var onRemoved: (@Sendable (HIDDeviceInfo) -> Void)?

    private let queue = DispatchQueue(label: "MouseControl.hid", qos: .userInitiated)
    private let matching: [[String: Int]]
    private var manager: IOHIDManager?
    /// Keyed by the IOHIDDevice pointer, which is what the input report callback identifies a sender by.
    private var connections: [UnsafeMutableRawPointer: HIDConnection] = [:]

    public init(matching: [[String: Int]]) {
        self.matching = matching
    }

    /// Matches Logitech HID++ collections: devices paired directly over Bluetooth, and USB receivers.
    public static func logitech() -> HIDTransport {
        HIDTransport(matching: [
            [
                kIOHIDVendorIDKey: SupportedDevices.logitechVendorID,
                kIOHIDDeviceUsagePageKey: SupportedDevices.bleHIDPPUsagePage,
                kIOHIDDeviceUsageKey: SupportedDevices.bleHIDPPUsage,
            ],
            [
                kIOHIDVendorIDKey: SupportedDevices.logitechVendorID,
                kIOHIDDeviceUsagePageKey: SupportedDevices.receiverHIDPPUsagePage,
                kIOHIDDeviceUsageKey: SupportedDevices.receiverHIDPPUsage,
            ],
        ])
    }

    /// Opens the manager. Returns `.notPermitted` when Input Monitoring hasn't been granted.
    public func start() -> StartResult {
        queue.sync {
            if manager != nil { return .ok }
            let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
            IOHIDManagerSetDeviceMatchingMultiple(manager, matching as CFArray)

            let context = Unmanaged.passUnretained(self).toOpaque()
            IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, device in
                Unmanaged<HIDTransport>.fromOpaque(context!).takeUnretainedValue().deviceMatched(device)
            }, context)
            IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, device in
                Unmanaged<HIDTransport>.fromOpaque(context!).takeUnretainedValue().deviceRemoved(device)
            }, context)
            // Registered on the manager, not per device: activation activates every matched device,
            // and registering a callback on an already-activated device traps.
            IOHIDManagerRegisterInputReportCallback(manager, { context, _, sender, _, reportID, report, length in
                guard let sender else { return }
                Unmanaged<HIDTransport>.fromOpaque(context!).takeUnretainedValue().connections[sender]?
                    .deliver(reportID: reportID, report: report, length: length)
            }, context)
            IOHIDManagerSetDispatchQueue(manager, queue)

            let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            guard result == kIOReturnSuccess else {
                Log.transport.error("IOHIDManagerOpen failed: \(String(format: "0x%08X", UInt32(bitPattern: result)), privacy: .public)")
                return result == kIOReturnNotPermitted ? .notPermitted : .failed(result)
            }
            IOHIDManagerActivate(manager)
            self.manager = manager
            Log.transport.info("HID manager started")
            return .ok
        }
    }

    public func stop() {
        queue.sync {
            guard let manager else { return }
            IOHIDManagerCancel(manager)
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            self.manager = nil
            connections.removeAll()
        }
    }

    // MARK: - Callbacks (transport queue)

    private func deviceMatched(_ device: IOHIDDevice) {
        let info = HIDDeviceInfo(service: IOHIDDeviceGetService(device))
        Log.transport.info("Matched \(info.product ?? "?", privacy: .public) pid=\(String(format: "0x%04X", info.productID), privacy: .public) via \(info.transport ?? "?", privacy: .public)")

        let connection = HIDConnection(device: device, info: info)
        connections[Unmanaged.passUnretained(device).toOpaque()] = connection
        onMatched?(connection)
    }

    private func deviceRemoved(_ device: IOHIDDevice) {
        guard let connection = connections.removeValue(forKey: Unmanaged.passUnretained(device).toOpaque()) else { return }
        connection.inputHandler = nil
        Log.transport.info("Removed \(connection.info.product ?? "?", privacy: .public)")
        onRemoved?(connection.info)
    }

    /// Must be called from `onMatched` (on the transport queue).
    public func setInputHandler(_ handler: @escaping @Sendable ([UInt8]) -> Void, for connection: HIDConnection) {
        dispatchPrecondition(condition: .onQueue(queue))
        connection.inputHandler = handler
    }
}
