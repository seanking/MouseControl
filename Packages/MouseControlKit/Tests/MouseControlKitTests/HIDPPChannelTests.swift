import Foundation
import Synchronization
import Testing
@testable import MouseControlKit

@Suite struct HIDPPChannelTests {
    /// A channel whose sender hands each outgoing report to `reply`, which may feed reports back.
    private func makeChannel(
        timeout: Duration = .milliseconds(200),
        reply: @escaping @Sendable (_ sent: [UInt8], _ channel: HIDPPChannel) -> Void
    ) -> HIDPPChannel {
        let box = Mutex<HIDPPChannel?>(nil)
        let channel = HIDPPChannel(deviceIndex: 0xFF, timeout: timeout) { sent in
            let channel = box.withLock { $0 }!
            DispatchQueue.global().async { reply(sent, channel) }
        }
        box.withLock { $0 = channel }
        return channel
    }

    @Test func matchesResponseBySoftwareID() async throws {
        let channel = makeChannel { sent, channel in
            #expect(sent == Fixture.getFeatureBatteryRequest)
            channel.receive(Fixture.getFeatureBatteryResponse)
        }
        let info = try await RootFeature(channel: channel).feature(.unifiedBattery)
        #expect(info == FeatureInfo(index: 0x08, type: 0, version: 0))
    }

    @Test func mapsErrorResponse() async {
        let channel = makeChannel { _, channel in channel.receive(Fixture.errorInvalidFunction) }
        await #expect(throws: HIDPPError.device(code: 7)) {
            _ = try await channel.request(featureIndex: 0, function: 0)
        }
    }

    @Test func mapsHIDPP10ErrorResponse() async {
        let channel = makeChannel { sent, channel in
            // Receiver-style error: [0x10, dev, 0x8F, origSubID, origAddress, code, 0]
            channel.receive([0x10, 0xFF, 0x8F, sent[2], sent[3], 0x09, 0x00])
        }
        await #expect(throws: HIDPPError.hidpp10(code: 9)) {
            _ = try await channel.request(featureIndex: 0x05, function: 2)
        }
    }

    @Test func ignoresStaleAndForeignResponsesThenTimesOut() async {
        let channel = makeChannel(timeout: .milliseconds(100)) { _, channel in
            // Wrong software ID (2), wrong device index, and a mouse report: none should match.
            channel.receive(Fixture.bytes("11 FF 00 02 08 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00"))
            channel.receive(Fixture.bytes("11 01 00 01 08 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00"))
            channel.receive(Fixture.mouseMovement)
        }
        await #expect(throws: HIDPPError.timeout) {
            _ = try await channel.request(featureIndex: 0, function: 0, params: [0x10, 0x04])
        }
    }

    @Test func rotatesSoftwareIDsSkippingZero() async throws {
        let seen = Mutex<[UInt8]>([])
        let channel = makeChannel { sent, channel in
            seen.withLock { $0.append(sent[3] & 0x0F) }
            var response = sent
            response[4] = 0x01
            channel.receive(response)
        }
        for _ in 0..<16 { _ = try await channel.request(featureIndex: 0, function: 1) }
        let ids = seen.withLock { $0 }
        #expect(ids == Array(1...15) + [1])
    }

    @Test func serializesConcurrentRequests() async throws {
        let inFlight = Mutex(0)
        let maxInFlight = Mutex(0)
        let channel = makeChannel { sent, channel in
            let now = inFlight.withLock { $0 += 1; return $0 }
            maxInFlight.withLock { $0 = max($0, now) }
            usleep(5_000)
            inFlight.withLock { $0 -= 1 }
            channel.receive(sent)
        }
        try await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0..<8 {
                group.addTask { _ = try await channel.request(featureIndex: UInt8(i), function: 1) }
            }
            try await group.waitForAll()
        }
        #expect(maxInFlight.withLock { $0 } == 1)
    }

    @Test func deliversNotifications() async throws {
        let channel = HIDPPChannel { _ in }
        channel.receive(Fixture.batteryEvent)
        channel.close()
        var received: [HIDPPMessage] = []
        for await message in channel.notifications { received.append(message) }
        #expect(received.count == 1)
        #expect(received.first?.featureIndex == 0x08)
        #expect(BatteryFeature.parseStatus(try #require(received.first).params)?.percentage == 85)
    }

    @Test func closeFailsPendingRequests() async {
        let channel = makeChannel(timeout: .seconds(5)) { _, channel in channel.close() }
        await #expect(throws: HIDPPError.disconnected) {
            _ = try await channel.request(featureIndex: 0, function: 0)
        }
    }

    @Test func requestAfterCloseFailsWithoutSending() async {
        let sent = Mutex(0)
        let channel = HIDPPChannel { _ in sent.withLock { $0 += 1 } }
        channel.close()
        await #expect(throws: HIDPPError.disconnected) {
            _ = try await channel.request(featureIndex: 0, function: 0)
        }
        #expect(sent.withLock { $0 } == 0)
    }

    @Test func sendFailurePropagates() async {
        let channel = HIDPPChannel { _ in throw HIDPPError.sendFailed(-536_870_212) }
        await #expect(throws: HIDPPError.sendFailed(-536_870_212)) {
            _ = try await channel.request(featureIndex: 0, function: 0)
        }
    }
}
