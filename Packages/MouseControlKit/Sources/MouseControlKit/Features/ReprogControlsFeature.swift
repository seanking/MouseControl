import Foundation

/// Reprogrammable Controls v4 (0x1B04).
/// fn0 getCount → [count]
/// fn1 getCidInfo(index) → [cid16, tid16, flags, pos, group, gmask, additionalFlags]
/// fn3 setCidReporting(cid16, flags, remap16); flags bit0 divert, bit1 divert-valid,
///     bit4 raw XY, bit5 raw-XY-valid
/// event fn0 divertedButtons → [cid16 × up to 4] currently pressed diverted controls
/// event fn1 divertedRawMouseXY → [dx16, dy16] signed; sent instead of pointer motion
///     while a control diverted with raw XY is held
public struct ReprogControlsFeature: Sendable {
    public struct Control: Equatable, Sendable {
        public let cid: UInt16
        public let taskID: UInt16
        /// Combined flags: low byte from `flags`, high byte from `additionalFlags`.
        public let flags: UInt16

        public var isDivertable: Bool { flags & 0x0020 != 0 }
        public var isReprogrammable: Bool { flags & 0x0010 != 0 }
        /// Can report pointer motion while held (additionalFlags bit0).
        public var supportsRawXY: Bool { flags & 0x0100 != 0 }
    }

    public static let divertedButtonsEvent: UInt8 = 0
    public static let rawXYEvent: UInt8 = 1

    public let index: UInt8
    let channel: any HIDPPRequesting

    public init(index: UInt8, channel: any HIDPPRequesting) {
        self.index = index
        self.channel = channel
    }

    public func controls() async throws -> [Control] {
        let count = try await channel.request(featureIndex: index, function: 0).params[0]
        var controls: [Control] = []
        for i in 0..<count {
            let r = try await channel.request(featureIndex: index, function: 1, params: [i])
            controls.append(Self.parseControl(r.params))
        }
        return controls
    }

    /// `rawXY`: nil leaves the control's raw XY reporting unchanged.
    public func setDiverted(_ diverted: Bool, cid: UInt16, rawXY: Bool? = nil) async throws {
        _ = try await channel.request(featureIndex: index, function: 3, params: Self.reportingParams(cid: cid, diverted: diverted, rawXY: rawXY))
    }

    static func parseControl(_ p: [UInt8]) -> Control {
        Control(
            cid: UInt16(p[0]) << 8 | UInt16(p[1]),
            taskID: UInt16(p[2]) << 8 | UInt16(p[3]),
            flags: UInt16(p[4]) | UInt16(p[8]) << 8
        )
    }

    static func reportingParams(cid: UInt16, diverted: Bool, rawXY: Bool? = nil) -> [UInt8] {
        // divert-valid (0x02) is always set so the divert bit is applied; remap 0 = unchanged.
        var flags: UInt8 = diverted ? 0x03 : 0x02
        if let rawXY { flags |= rawXY ? 0x30 : 0x20 }
        return cid.bigEndianBytes + [flags, 0x00, 0x00]
    }

    /// Pointer motion from a divertedRawMouseXY event.
    public static func rawXY(inEvent p: [UInt8]) -> (dx: Int, dy: Int)? {
        guard p.count >= 4 else { return nil }
        let dx = Int16(bitPattern: UInt16(p[0]) << 8 | UInt16(p[1]))
        let dy = Int16(bitPattern: UInt16(p[2]) << 8 | UInt16(p[3]))
        return (Int(dx), Int(dy))
    }

    /// CIDs currently held down, from a divertedButtons event.
    public static func pressedControls(inEvent p: [UInt8]) -> Set<UInt16> {
        var pressed: Set<UInt16> = []
        var offset = 0
        while offset + 1 < min(p.count, 8) {
            let cid = UInt16(p[offset]) << 8 | UInt16(p[offset + 1])
            if cid != 0 { pressed.insert(cid) }
            offset += 2
        }
        return pressed
    }
}

/// Wireless Device Status (0x1D4B). event fn0 → [status, request, reason]
/// status 1 = reconnection; request 1 = software reconfiguration needed.
public enum WirelessDeviceStatus {
    public static func needsReconfiguration(event p: [UInt8]) -> Bool {
        p.count >= 2 && (p[0] == 1 || p[1] == 1)
    }
}
