import Foundation
import os
import Synchronization

/// Anything that can perform a HID++ request. Features talk to this, so tests can substitute fixtures.
public protocol HIDPPRequesting: Sendable {
    /// Sends `function` on `featureIndex` and returns the matching response.
    func request(featureIndex: UInt8, function: UInt8, params: [UInt8]) async throws -> HIDPPMessage
}

extension HIDPPRequesting {
    public func request(featureIndex: UInt8, function: UInt8) async throws -> HIDPPMessage {
        try await request(featureIndex: featureIndex, function: function, params: [])
    }
}

/// HID++ 2.0 request/response matching over an arbitrary report transport.
///
/// - Requests are serialized (one in flight) because BLE devices drop requests when flooded.
/// - Each request carries a rotating software ID (1...15) in the low nibble of the function byte;
///   responses are matched on (featureIndex, functionByte). Software ID 0 marks device notifications.
/// - Incoming reports are fed in via `receive(_:)` from the transport's callback queue.
public final class HIDPPChannel: HIDPPRequesting, Sendable {
    public typealias Sender = @Sendable ([UInt8]) throws -> Void

    private struct Key: Hashable {
        let featureIndex: UInt8
        let functionByte: UInt8
    }

    private struct State {
        var nextSoftwareID: UInt8 = 1
        var pending: [Key: CheckedContinuation<HIDPPMessage, any Error>] = [:]
        var closed = false
    }

    public let deviceIndex: UInt8
    public let timeout: Duration
    /// Unsolicited reports (software ID 0): battery events, diverted buttons, wireless status, …
    public let notifications: AsyncStream<HIDPPMessage>

    private let send: Sender
    private let state = Mutex(State())
    private let gate = AsyncGate()
    private let notificationSink: AsyncStream<HIDPPMessage>.Continuation

    public init(deviceIndex: UInt8 = HIDPP.bluetoothDeviceIndex, timeout: Duration = .seconds(1), send: @escaping Sender) {
        self.deviceIndex = deviceIndex
        self.timeout = timeout
        self.send = send
        (notifications, notificationSink) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(32))
    }

    @concurrent
    public func request(featureIndex: UInt8, function: UInt8, params: [UInt8]) async throws -> HIDPPMessage {
        await gate.enter()
        do {
            let response = try await performRequest(featureIndex: featureIndex, function: function, params: params)
            await gate.leave()
            return response
        } catch {
            await gate.leave()
            throw error
        }
    }

    private func performRequest(featureIndex: UInt8, function: UInt8, params: [UInt8]) async throws -> HIDPPMessage {
        let softwareID = state.withLock { s in
            let id = s.nextSoftwareID
            s.nextSoftwareID = id >= 0x0F ? 1 : id + 1
            return id
        }
        let message = HIDPPMessage.longRequest(
            deviceIndex: deviceIndex, featureIndex: featureIndex,
            function: function, softwareID: softwareID, params: params
        )
        let key = Key(featureIndex: featureIndex, functionByte: message.functionByte)
        let timeout = self.timeout

        return try await withCheckedThrowingContinuation { continuation in
            let registered = state.withLock { s -> Bool in
                guard !s.closed else { return false }
                s.pending[key] = continuation
                return true
            }
            guard registered else {
                continuation.resume(throwing: HIDPPError.disconnected)
                return
            }
            Log.hidpp.debug("→ \(message.description, privacy: .public)")
            do {
                try send(message.bytes)
            } catch {
                take(key)?.resume(throwing: error)
                return
            }
            let seconds = Double(timeout.components.seconds) + Double(timeout.components.attoseconds) / 1e18
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + seconds) { [weak self] in
                self?.take(key)?.resume(throwing: HIDPPError.timeout)
            }
        }
    }

    private func take(_ key: Key) -> CheckedContinuation<HIDPPMessage, any Error>? {
        state.withLock { $0.pending.removeValue(forKey: key) }
    }

    /// Feeds a raw input report (starting with the report ID). Non-HID++ reports are ignored cheaply.
    public func receive(_ bytes: [UInt8]) {
        guard let message = HIDPPMessage(bytes: bytes), message.deviceIndex == deviceIndex else { return }
        Log.hidpp.debug("← \(message.description, privacy: .public)")

        if message.isHIDPP20Error || message.isHIDPP10Error {
            // [reportID, dev, 0xFF | 0x8F, origFeatureIndex, origFunctionByte, errorCode, …]
            // The original feature index sits in the function-byte slot.
            let key = Key(featureIndex: message.functionByte, functionByte: message.params[0])
            let code = message.params[1]
            take(key)?.resume(throwing: message.isHIDPP20Error ? HIDPPError.device(code: code) : HIDPPError.hidpp10(code: code))
            return
        }
        if message.softwareID == 0 {
            notificationSink.yield(message)
            return
        }
        let key = Key(featureIndex: message.featureIndex, functionByte: message.functionByte)
        // A response with no pending request is stale (arrived after a timeout); drop it.
        take(key)?.resume(returning: message)
    }

    /// Fails all pending requests and ends the notification stream. Call when the device goes away.
    public func close() {
        let pending = state.withLock { s in
            s.closed = true
            defer { s.pending.removeAll() }
            return Array(s.pending.values)
        }
        pending.forEach { $0.resume(throwing: HIDPPError.disconnected) }
        notificationSink.finish()
    }

    deinit {
        notificationSink.finish()
    }
}

/// A FIFO async mutex: one HID++ request in flight at a time.
actor AsyncGate {
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func enter() async {
        if !busy {
            busy = true
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    func leave() {
        if waiters.isEmpty {
            busy = false
        } else {
            waiters.removeFirst().resume()
        }
    }
}
