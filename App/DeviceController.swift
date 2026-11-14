import AppKit
import MouseControlKit
import Observation
import os

/// Coordinates the supported kinds of mouse and owns app-wide state: permissions, the login item,
/// and system notifications, which it forwards to each device.
@MainActor @Observable
final class DeviceController {
    let settings: SettingsStore
    let logitech: LogitechMouse
    let magicMouse: MagicMouse

    private(set) var inputMonitoringGranted = Permission.inputMonitoring.isGranted
    private(set) var accessibilityGranted = Permission.accessibility.isGranted
    private(set) var launchAtLogin = LoginItem.isEnabled
    private(set) var launchAtLoginNeedsApproval = LoginItem.needsApproval
    private(set) var lastError: String?

    @ObservationIgnored private let logger = Logger(subsystem: Log.subsystem, category: "controller")
    @ObservationIgnored private var observers: [any NSObjectProtocol] = []
    @ObservationIgnored private var started = false

    init() {
        let settings = SettingsStore()
        self.settings = settings
        logitech = LogitechMouse(settings: settings)
        magicMouse = MagicMouse(settings: settings)
    }

    /// Every supported kind, in menu order.
    private var devices: [any MouseDevice] { [logitech, magicMouse] }

    var connectedDevices: [any MouseDevice] { devices.filter(\.isConnected) }

    // MARK: - Lifecycle

    func start() {
        guard !started else { return }
        started = true

        if !settings.didInitialLoginItemSetup {
            settings.didInitialLoginItemSetup = true
            setLaunchAtLogin(true)
        }
        // The warning is on by default, so ask now rather than only when the setting changes.
        // macOS shows the prompt only while authorization is undetermined.
        if settings.lowBatteryThreshold > 0 { BatteryNotifier.requestAuthorization() }

        devices.forEach { $0.start() }
        observeSystem()
    }

    private func observeSystem() {
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.logger.info("Woke from sleep; re-applying settings")
                self.refreshPermissions()
                self.devices.forEach { $0.didWake() }
            }
        })

        let distributed = DistributedNotificationCenter.default()
        // System Settings › Mouse/Trackpad "Natural scrolling" changed.
        observers.append(distributed.addObserver(forName: .init("SwipeScrollDirectionDidChangeNotification"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.logitech.systemScrollDirectionChanged()
            }
        })
        // Posted when the Accessibility trust list changes. The TCC database updates slightly later.
        observers.append(distributed.addObserver(forName: .init("com.apple.accessibility.api"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(500))
                self?.refreshPermissions()
            }
        })
    }

    /// Re-reads permission and login-item state. Called when the menu opens and on system events.
    func refreshPermissions() {
        let inputMonitoring = Permission.inputMonitoring.isGranted
        let accessibility = Permission.accessibility.isGranted
        let accessibilityChanged = accessibility != accessibilityGranted
        inputMonitoringGranted = inputMonitoring
        accessibilityGranted = accessibility
        logitech.permissionsChanged(inputMonitoringGranted: inputMonitoring, accessibilityChanged: accessibilityChanged)
        launchAtLogin = LoginItem.isEnabled
        launchAtLoginNeedsApproval = LoginItem.needsApproval
    }

    // MARK: - UI actions

    func setShowBatteryInMenuBar(_ show: Bool) {
        settings.showBatteryInMenuBar = show
    }

    func setLowBatteryThreshold(_ threshold: Int) {
        settings.lowBatteryThreshold = threshold
        if threshold > 0 { BatteryNotifier.requestAuthorization() }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LoginItem.setEnabled(enabled)
            lastError = nil
        } catch {
            logger.error("Login item: \(error.localizedDescription, privacy: .public)")
            lastError = "Launch at Login: \(error.localizedDescription)"
        }
        launchAtLogin = LoginItem.isEnabled
        launchAtLoginNeedsApproval = LoginItem.needsApproval
    }

    func relaunch() {
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: config) { _, _ in
            Task { @MainActor in NSApp.terminate(nil) }
        }
    }
}
