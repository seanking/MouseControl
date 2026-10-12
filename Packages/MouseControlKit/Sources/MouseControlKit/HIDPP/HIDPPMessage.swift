import Foundation

/// Constants for HID++ framing.
public enum HIDPP {
    public static let shortReportID: UInt8 = 0x10
    public static let longReportID: UInt8 = 0x11
    /// Total report length including the report ID byte.
    public static let shortReportLength = 7
    public static let longReportLength = 20
    public static let shortParamsLength = shortReportLength - 4
    public static let longParamsLength = longReportLength - 4

    /// Device index used for a device connected directly over Bluetooth.
    public static let bluetoothDeviceIndex: UInt8 = 0xFF
    /// Device indexes a receiver assigns to its paired devices.
    public static let receiverSlots: ClosedRange<UInt8> = 1...6
    /// Feature index used by HID++ 2.0 error responses.
    public static let errorFeatureIndex: UInt8 = 0xFF
    /// Sub ID used by HID++ 1.0 error responses (receivers).
    public static let hidpp10ErrorSubID: UInt8 = 0x8F
}

/// A single HID++ report:
/// `[reportID, deviceIndex, featureIndex, function << 4 | softwareID, params...]`.
public struct HIDPPMessage: Equatable, Sendable, CustomStringConvertible {
    public var reportID: UInt8
    public var deviceIndex: UInt8
    public var featureIndex: UInt8
    /// Function byte: function ID in the high nibble, software ID in the low nibble.
    public var functionByte: UInt8
    public var params: [UInt8]

    public var functionID: UInt8 { functionByte >> 4 }
    public var softwareID: UInt8 { functionByte & 0x0F }

    public init(reportID: UInt8, deviceIndex: UInt8, featureIndex: UInt8, functionByte: UInt8, params: [UInt8]) {
        self.reportID = reportID
        self.deviceIndex = deviceIndex
        self.featureIndex = featureIndex
        self.functionByte = functionByte
        self.params = params
    }

    /// Builds a long (20-byte) request. Params are zero-padded/truncated to 16 bytes.
    public static func longRequest(
        deviceIndex: UInt8, featureIndex: UInt8, function: UInt8, softwareID: UInt8, params: [UInt8] = []
    ) -> HIDPPMessage {
        precondition(function <= 0x0F && softwareID <= 0x0F, "function and software ID are 4-bit values")
        return HIDPPMessage(
            reportID: HIDPP.longReportID,
            deviceIndex: deviceIndex,
            featureIndex: featureIndex,
            functionByte: function << 4 | softwareID,
            params: padded(params, to: HIDPP.longParamsLength)
        )
    }

    /// Parses a raw report (starting with the report ID byte). Returns nil for non-HID++ reports.
    public init?(bytes: some Collection<UInt8>) {
        let b = Array(bytes)
        guard let id = b.first else { return nil }
        let expected: Int
        switch id {
        case HIDPP.shortReportID: expected = HIDPP.shortReportLength
        case HIDPP.longReportID: expected = HIDPP.longReportLength
        default: return nil
        }
        guard b.count >= expected else { return nil }
        self.init(
            reportID: id,
            deviceIndex: b[1],
            featureIndex: b[2],
            functionByte: b[3],
            params: Array(b[4..<expected])
        )
    }

    public var bytes: [UInt8] {
        let length = reportID == HIDPP.shortReportID ? HIDPP.shortParamsLength : HIDPP.longParamsLength
        return [reportID, deviceIndex, featureIndex, functionByte] + Self.padded(params, to: length)
    }

    /// True for HID++ 2.0 error responses (`featureIndex == 0xFF`).
    public var isHIDPP20Error: Bool { featureIndex == HIDPP.errorFeatureIndex }
    /// True for HID++ 1.0 error responses (short report, sub ID `0x8F`).
    public var isHIDPP10Error: Bool { reportID == HIDPP.shortReportID && featureIndex == HIDPP.hidpp10ErrorSubID }

    /// Reads a big-endian UInt16 from `params` at `offset` (0 if out of range).
    public func u16(at offset: Int) -> UInt16 {
        guard offset + 1 < params.count else { return 0 }
        return UInt16(params[offset]) << 8 | UInt16(params[offset + 1])
    }

    public var description: String {
        bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    static func padded(_ params: [UInt8], to length: Int) -> [UInt8] {
        if params.count >= length { return Array(params.prefix(length)) }
        return params + [UInt8](repeating: 0, count: length - params.count)
    }
}

extension UInt16 {
    /// Big-endian bytes, as HID++ transmits multi-byte values.
    var bigEndianBytes: [UInt8] { [UInt8(self >> 8), UInt8(self & 0xFF)] }
}
