import Foundation
import MouseControlKit
import Observation
import os

/// An Apple Magic Mouse. macOS drives it directly, so the app only watches for it, reads its
/// battery from the IORegistry, and applies the tracking speed whenever one connects.
@MainActor @Observable
final class MagicMouse: MouseDevice {
    /// The mouse shown in the menu: the most recently connected one.
    private(set) var device: HIDDeviceInfo?
    private(set) var battery: BatteryStatus?

    var isConnected: Bool { device != nil }
    var name: String { device?.product ?? "Magic Mouse" }
    /// The chosen speed, or the system's current one until the user picks a speed.
    var trackingSpeed: Double { settings.magicMouseTrackingSpeed ?? TrackingSpeed.current ?? 1 }

    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let logger = Logger(subsystem: Log.subsystem, category: "magicmouse")
    @ObservationIgnored private let monitor = DeviceMonitor.magicMouse()
    @ObservationIgnored private let batteryNotifier = BatteryNotifier()
    /// Every connected Magic Mouse, oldest first.
    @ObservationIgnored private var connected: [HIDDeviceInfo] = []
    @ObservationIgnored private var applyTask: Task<Void, Never>?
    @ObservationIgnored private var batteryPoll: Task<Void, Never>?
    @ObservationIgnored private var started = false

    private static let batteryPollInterval: Duration = .seconds(300)
    /// The registry reports the mouse before the HID event system has set up its pointer service
    /// (which starts from the default speed) or read the battery.
    private static let settleDelay: Duration = .seconds(1)

    init(settings: SettingsStore) {
        self.settings = settings
    }

    func start() {
        guard !started else { return }
        started = true
        monitor.onMatched = { [weak self] info in
            Task { @MainActor in self?.matched(info) }
        }
        monitor.onRemoved = { [weak self] info in
            Task { @MainActor in self?.removed(info) }
        }
        monitor.start()
    }

    func didWake() {
        if isConnected { scheduleApply(after: Self.settleDelay) }
    }

    func setTrackingSpeed(_ speed: Double) {
        settings.magicMouseTrackingSpeed = speed
        applyTask?.cancel()
        applyTrackingSpeed()
    }

    // MARK: - Device events

    private func matched(_ info: HIDDeviceInfo) {
        connected.append(info)
        device = info
        scheduleApply(after: Self.settleDelay)
        startBatteryPoll()
    }

    private func removed(_ info: HIDDeviceInfo) {
        connected.removeAll { $0.registryID == info.registryID }
        guard device?.registryID == info.registryID else { return }
        device = connected.last
        battery = nil
        if device == nil {
            applyTask?.cancel()
            batteryPoll?.cancel()
        } else {
            refreshBattery()
        }
    }

    // MARK: - Applying settings

    private func scheduleApply(after delay: Duration) {
        applyTask?.cancel()
        applyTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.applyTrackingSpeed()
            self?.refreshBattery()
        }
    }

    /// Leaves the system's speed alone until the user picks one.
    private func applyTrackingSpeed() {
        guard isConnected, let speed = settings.magicMouseTrackingSpeed else { return }
        if TrackingSpeed.apply(speed) {
            logger.info("Tracking speed set to \(speed, privacy: .public)")
        } else {
            logger.error("HID event system rejected tracking speed \(speed, privacy: .public)")
        }
    }

    // MARK: - Battery

    private func refreshBattery() {
        guard let device, let percent = HIDRegistry.batteryPercent(of: device) else { return }
        let status = BatteryStatus(percentage: percent)
        battery = status
        batteryNotifier.update(status, deviceName: name, threshold: settings.lowBatteryThreshold)
    }

    private func startBatteryPoll() {
        batteryPoll?.cancel()
        batteryPoll = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.batteryPollInterval)
                guard !Task.isCancelled else { return }
                self?.refreshBattery()
            }
        }
    }
}
