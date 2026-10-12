import Foundation

/// Root (0x0000) — always at feature index 0.
/// fn0 getFeature(featureID) → [index, type, version]; fn1 ping(0, 0, data) → [major, minor, data]
public struct RootFeature: Sendable {
    public static let index: UInt8 = 0
    let channel: any HIDPPRequesting

    public init(channel: any HIDPPRequesting) { self.channel = channel }

    public struct ProtocolVersion: Equatable, Sendable {
        public let major: UInt8
        public let minor: UInt8
    }

    /// Returns nil when the device doesn't implement `feature`.
    public func feature(_ feature: FeatureID) async throws -> FeatureInfo? {
        let r = try await channel.request(featureIndex: Self.index, function: 0, params: feature.rawValue.bigEndianBytes)
        return Self.parseGetFeature(r.params, for: feature)
    }

    public func ping(data: UInt8 = 0x5A) async throws -> ProtocolVersion {
        let r = try await channel.request(featureIndex: Self.index, function: 1, params: [0, 0, data])
        guard r.params[2] == data else { throw HIDPPError.malformedResponse }
        return ProtocolVersion(major: r.params[0], minor: r.params[1])
    }

    static func parseGetFeature(_ p: [UInt8], for feature: FeatureID) -> FeatureInfo? {
        guard p.count >= 3 else { return nil }
        // Index 0 means "not present" for everything except Root itself.
        if p[0] == 0 && feature != .root { return nil }
        return FeatureInfo(index: p[0], type: p[1], version: p[2])
    }
}

/// Discovers runtime feature indexes for a set of features. Missing features are simply absent.
public func discoverFeatures(
    _ features: [FeatureID], channel: any HIDPPRequesting
) async throws -> [FeatureID: FeatureInfo] {
    let root = RootFeature(channel: channel)
    var result: [FeatureID: FeatureInfo] = [:]
    for id in features {
        do {
            if let info = try await root.feature(id) { result[id] = info }
        } catch HIDPPError.device {
            continue
        }
    }
    return result
}
