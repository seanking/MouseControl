import Foundation
import Synchronization
@testable import MouseControlKit

/// Byte fixtures for an MX Master 3S over Bluetooth (device index 0xFF), long reports.
///
/// Layouts follow Solaar/logiops. Replace with real captures from
/// `log stream --level debug --predicate 'category == "hidpp"'` when available.
enum Fixture {
    /// Parses "11 FF 00 1A ..." into bytes.
    static func bytes(_ hex: String) -> [UInt8] {
        hex.split(separator: " ").map { UInt8($0, radix: 16)! }
    }

    // Root.getFeature(0x1004) → index 0x08, type 0, version 0  (swid 1)
    static let getFeatureBatteryRequest = bytes("11 FF 00 01 10 04 00 00 00 00 00 00 00 00 00 00 00 00 00 00")
    static let getFeatureBatteryResponse = bytes("11 FF 00 01 08 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00")

    // Error: getFeature on a bad function → InvalidFunctionID (7)
    static let errorInvalidFunction = bytes("11 FF FF 00 01 07 00 00 00 00 00 00 00 00 00 00 00 00 00 00")

    // Battery event notification (swid 0) on index 0x08: 85%, good, charging, external power
    static let batteryEvent = bytes("11 FF 08 00 55 04 01 01 00 00 00 00 00 00 00 00 00 00 00 00")

    // Standard mouse input report (report ID 0x02) — must be ignored.
    static let mouseMovement = bytes("02 00 01 00 FF 00 00")
}

/// A scripted device: answers requests by (featureIndex, function) from a table of response params.
final class FixtureDevice: HIDPPRequesting, Sendable {
    struct Call: Equatable, Sendable {
        let featureIndex: UInt8
        let function: UInt8
        let params: [UInt8]
    }

    private let responder: @Sendable (Call) throws -> [UInt8]
    private let log = Mutex<[Call]>([])

    init(_ responder: @escaping @Sendable (Call) throws -> [UInt8]) {
        self.responder = responder
    }

    var calls: [Call] { log.withLock { $0 } }

    func request(featureIndex: UInt8, function: UInt8, params: [UInt8]) async throws -> HIDPPMessage {
        let call = Call(featureIndex: featureIndex, function: function, params: params)
        log.withLock { $0.append(call) }
        let response = try responder(call)
        return HIDPPMessage(
            reportID: HIDPP.longReportID, deviceIndex: 0xFF, featureIndex: featureIndex,
            functionByte: function << 4 | 1, params: HIDPPMessage.padded(response, to: 16)
        )
    }
}
