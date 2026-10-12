import Foundation

/// Adjustable DPI (0x2201).
/// fn1 getSensorDpiList(sensor) → [sensor, dpi16, dpi16, …, 0x0000]
///     A value with the top three bits set (0xE000) is a step: `step = value & 0x1FFF`, meaning
///     "from the previous value to the next value in increments of step".
/// fn2 getSensorDpi(sensor) → [sensor, dpi16, defaultDpi16]
/// fn3 setSensorDpi(sensor, dpi16) → [sensor, dpi16]
public struct AdjustableDPIFeature: Sendable {
    public let index: UInt8
    public let sensor: UInt8
    let channel: any HIDPPRequesting

    public init(index: UInt8, sensor: UInt8 = 0, channel: any HIDPPRequesting) {
        self.index = index
        self.sensor = sensor
        self.channel = channel
    }

    public func supportedDPIs() async throws -> [Int] {
        let r = try await channel.request(featureIndex: index, function: 1, params: [sensor])
        let list = Self.parseDPIList(r.params)
        guard !list.isEmpty else { throw HIDPPError.malformedResponse }
        return list
    }

    public func currentDPI() async throws -> (current: Int, defaultDPI: Int) {
        let r = try await channel.request(featureIndex: index, function: 2, params: [sensor])
        return (Int(r.u16(at: 1)), Int(r.u16(at: 3)))
    }

    public func setDPI(_ dpi: Int) async throws {
        _ = try await channel.request(featureIndex: index, function: 3, params: [sensor] + UInt16(dpi).bigEndianBytes)
    }

    static func parseDPIList(_ p: [UInt8]) -> [Int] {
        var result: [Int] = []
        var pendingStep: Int?
        var offset = 1  // skip sensor index
        while offset + 1 < p.count {
            let value = Int(p[offset]) << 8 | Int(p[offset + 1])
            offset += 2
            if value == 0 { break }
            if value >> 13 == 0b111 {
                pendingStep = value & 0x1FFF
                continue
            }
            if let step = pendingStep, step > 0, let last = result.last {
                var dpi = last + step
                while dpi < value {
                    result.append(dpi)
                    dpi += step
                }
            }
            pendingStep = nil
            result.append(value)
        }
        return Array(Set(result)).sorted()
    }

    /// Nearest supported value to `dpi` (ties go to the lower value).
    public static func snap(_ dpi: Int, to supported: [Int]) -> Int? {
        supported.min { abs($0 - dpi) < abs($1 - dpi) || (abs($0 - dpi) == abs($1 - dpi) && $0 < $1) }
    }
}
