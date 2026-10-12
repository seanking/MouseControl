import Foundation

public struct BatteryStatus: Equatable, Sendable {
    public enum Level: Sendable, Equatable {
        case critical, low, good, full, unknown
    }

    public enum Charging: Sendable, Equatable {
        case discharging, charging, chargingSlow, full, error

        public var isCharging: Bool { self == .charging || self == .chargingSlow }
    }

    /// 0–100. Approximated from `level` when the device can't report state of charge.
    public let percentage: Int
    public let level: Level
    public let charging: Charging
    public let externalPower: Bool
}

/// Unified Battery (0x1004).
/// fn0 getCapabilities → [supportedLevels, flags]; flags bit1 = state-of-charge supported
/// fn1 getStatus → [stateOfCharge, levelBits, chargingStatus, externalPower]
/// event fn0 → same payload as getStatus
public struct BatteryFeature: Sendable {
    public let index: UInt8
    let channel: any HIDPPRequesting

    public init(index: UInt8, channel: any HIDPPRequesting) {
        self.index = index
        self.channel = channel
    }

    public func status() async throws -> BatteryStatus {
        let r = try await channel.request(featureIndex: index, function: 1)
        guard let status = Self.parseStatus(r.params) else { throw HIDPPError.malformedResponse }
        return status
    }

    /// Parses getStatus responses and battery event notifications (identical layout).
    public static func parseStatus(_ p: [UInt8]) -> BatteryStatus? {
        guard p.count >= 4 else { return nil }
        let level: BatteryStatus.Level =
            if p[1] & 0x08 != 0 { .full }
            else if p[1] & 0x04 != 0 { .good }
            else if p[1] & 0x02 != 0 { .low }
            else if p[1] & 0x01 != 0 { .critical }
            else { .unknown }
        let charging: BatteryStatus.Charging =
            switch p[2] {
            case 0: .discharging
            case 1: .charging
            case 2: .chargingSlow
            case 3: .full
            default: .error
            }
        var percentage = Int(p[0])
        if percentage == 0 || percentage > 100 {
            // Device doesn't report state of charge; approximate from the level bits.
            percentage = switch level {
            case .full: 90
            case .good: 50
            case .low: 20
            case .critical: 5
            case .unknown: 0
            }
        }
        return BatteryStatus(percentage: percentage, level: level, charging: charging, externalPower: p[3] != 0)
    }
}
