import Foundation

/// Hi-Res Wheel (0x2121).
/// fn1 getWheelMode → [mode]; fn2 setWheelMode(mode) → [mode]
/// mode bit0 = target (1: HID++ notifications / diverted), bit1 = high resolution, bit2 = inverted
public struct HiResWheelFeature: Sendable {
    public struct Mode: OptionSet, Sendable, Equatable {
        public let rawValue: UInt8
        public init(rawValue: UInt8) { self.rawValue = rawValue }

        public static let diverted = Mode(rawValue: 0x01)
        public static let highResolution = Mode(rawValue: 0x02)
        public static let inverted = Mode(rawValue: 0x04)
    }

    public let index: UInt8
    let channel: any HIDPPRequesting

    public init(index: UInt8, channel: any HIDPPRequesting) {
        self.index = index
        self.channel = channel
    }

    public func mode() async throws -> Mode {
        let r = try await channel.request(featureIndex: index, function: 1)
        return Mode(rawValue: r.params[0])
    }

    public func setMode(_ mode: Mode) async throws {
        _ = try await channel.request(featureIndex: index, function: 2, params: [mode.rawValue])
    }

    /// Sets the invert bit (keeping resolution, forcing native HID reporting) and verifies by reading back.
    /// Returns false if the device didn't take the setting.
    public func setInverted(_ inverted: Bool) async throws -> Bool {
        let desired = Self.mode(from: try await mode(), inverted: inverted)
        try await setMode(desired)
        return try await mode().contains(.inverted) == inverted
    }

    static func mode(from current: Mode, inverted: Bool) -> Mode {
        var mode = current
        mode.remove(.diverted)
        if inverted { mode.insert(.inverted) } else { mode.remove(.inverted) }
        return mode
    }
}

/// Decides the device invert flag for a desired mouse scroll direction.
///
/// macOS applies one "natural scrolling" preference to every pointing device. To give the mouse its own
/// direction, the device inverts its wheel whenever the desired mouse direction differs from the system's.
public enum ScrollDirectionPolicy {
    public static func deviceInvert(mouseNatural: Bool, systemNatural: Bool) -> Bool {
        mouseNatural != systemNatural
    }
}
