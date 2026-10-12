import Foundation

/// Device Name & Type (0x0005). Used to identify a device paired to a receiver, where the
/// HID product ID belongs to the receiver rather than the mouse.
/// fn0 getDeviceNameCount → [length]
/// fn1 getDeviceName(charIndex) → [chars…] (up to 16 bytes, zero-padded)
public struct DeviceNameFeature: Sendable {
    public let index: UInt8
    let channel: any HIDPPRequesting

    public init(index: UInt8, channel: any HIDPPRequesting) {
        self.index = index
        self.channel = channel
    }

    public func name() async throws -> String {
        let count = Int(try await channel.request(featureIndex: index, function: 0).params[0])
        var bytes: [UInt8] = []
        while bytes.count < count {
            let chunk = try await channel.request(featureIndex: index, function: 1, params: [UInt8(bytes.count)]).params
            let chars = chunk.prefix(count - bytes.count).prefix { $0 != 0 }
            // A short or empty chunk means the device ended the name early.
            guard !chars.isEmpty else { break }
            bytes += chars
        }
        return String(decoding: bytes, as: UTF8.self)
    }
}
