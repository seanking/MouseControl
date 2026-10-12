import Foundation

/// HID++ 2.0 error codes returned in error responses.
public enum HIDPP20ErrorCode: UInt8, Sendable {
    case noError = 0
    case unknown = 1
    case invalidArgument = 2
    case outOfRange = 3
    case hardwareError = 4
    case logitechInternal = 5
    case invalidFeatureIndex = 6
    case invalidFunctionID = 7
    case busy = 8
    case unsupported = 9
}

public enum HIDPPError: Error, Equatable, Sendable, CustomStringConvertible {
    /// The device answered with a HID++ 2.0 error response.
    case device(code: UInt8)
    /// The device (or receiver) answered with a HID++ 1.0 error response.
    case hidpp10(code: UInt8)
    case timeout
    case sendFailed(Int32)
    case featureNotSupported(FeatureID)
    case malformedResponse
    case disconnected

    public var description: String {
        switch self {
        case .device(let code):
            if let known = HIDPP20ErrorCode(rawValue: code) { return "HID++ error \(known) (\(code))" }
            return "HID++ error \(code)"
        case .hidpp10(let code): return "HID++ 1.0 error \(code)"
        case .timeout: return "Device did not respond"
        case .sendFailed(let r): return String(format: "Report send failed (0x%08X)", UInt32(bitPattern: r))
        case .featureNotSupported(let id): return "Feature \(id) not supported"
        case .malformedResponse: return "Malformed response"
        case .disconnected: return "Device disconnected"
        }
    }
}
