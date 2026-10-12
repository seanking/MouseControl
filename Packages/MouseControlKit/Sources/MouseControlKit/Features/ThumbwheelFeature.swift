import Foundation

/// Thumbwheel (0x2150).
/// fn1 getThumbwheelStatus → [reportingMode, invert, …]
/// fn2 setThumbwheelReporting(reportingMode, invert); reportingMode 0 = native HID, 1 = diverted
public struct ThumbwheelFeature: Sendable {
    public struct Status: Equatable, Sendable {
        public let diverted: Bool
        public let inverted: Bool
    }

    public let index: UInt8
    let channel: any HIDPPRequesting

    public init(index: UInt8, channel: any HIDPPRequesting) {
        self.index = index
        self.channel = channel
    }

    public func status() async throws -> Status {
        let r = try await channel.request(featureIndex: index, function: 1)
        return Self.parseStatus(r.params)
    }

    /// Keeps native reporting and sets the invert flag.
    public func setInverted(_ inverted: Bool) async throws {
        _ = try await channel.request(featureIndex: index, function: 2, params: Self.reportingParams(diverted: false, inverted: inverted))
    }

    static func parseStatus(_ p: [UInt8]) -> Status {
        Status(diverted: p[0] & 0x01 != 0, inverted: p[1] & 0x01 != 0)
    }

    static func reportingParams(diverted: Bool, inverted: Bool) -> [UInt8] {
        [diverted ? 1 : 0, inverted ? 1 : 0]
    }
}
