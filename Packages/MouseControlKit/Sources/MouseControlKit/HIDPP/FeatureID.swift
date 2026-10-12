import Foundation

/// A HID++ 2.0 feature identifier. Runtime *indexes* are discovered per device via Root.getFeature.
public struct FeatureID: RawRepresentable, Hashable, Sendable, CustomStringConvertible {
    public let rawValue: UInt16
    public init(rawValue: UInt16) { self.rawValue = rawValue }

    public static let root = FeatureID(rawValue: 0x0000)
    public static let featureSet = FeatureID(rawValue: 0x0001)
    public static let unifiedBattery = FeatureID(rawValue: 0x1004)
    public static let reprogControlsV4 = FeatureID(rawValue: 0x1B04)
    public static let wirelessDeviceStatus = FeatureID(rawValue: 0x1D4B)
    public static let hiResWheel = FeatureID(rawValue: 0x2121)
    public static let thumbwheel = FeatureID(rawValue: 0x2150)
    public static let adjustableDPI = FeatureID(rawValue: 0x2201)

    public var description: String { String(format: "0x%04X", rawValue) }
}

/// Result of Root.getFeature.
public struct FeatureInfo: Equatable, Sendable {
    public let index: UInt8
    public let type: UInt8
    public let version: UInt8
}
