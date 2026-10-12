import AppKit
import MouseControlKit
import Observation
import os

/// Owns the device connection, applies settings, and publishes UI state on the main actor.
/// HID I/O happens on the transport queue and the cooperative pool, never on the main thread.
@MainActor @Observable
final class DeviceController {
    enum ConnectionState: Equatable {
        case searching
        case connected
        case notFound
        case permissionRequired
        case failed(String)
    }

    let settings = SettingsStore()

    private(set) var connection: ConnectionState = .searching
    private(set) var deviceName: String?
    private(set) var battery: BatteryStatus?
    private(set) var supportedDPIs: [Int] = []
    private(set) var currentDPI: Int?
    private(set) var inputMonitoringGranted = Permission.inputMonitoring.isGranted
    private(set) var accessibilityGranted = Permission.accessibility.isGranted
    /// Input Monitoring was granted after launch but the HID manager still can't open; macOS needs a relaunch.
    private(set) var needsRelaunch = false
    private(set) var scrollFallbackActive = false
    private(set) var gestureButtonAvailable: Bool?
    private(set) var launchAtLogin = LoginItem.isEnabled
    private(set) var launchAtLoginNeedsApproval = LoginItem.needsApproval
    private(set) var lastError: String?

    @ObservationIgnored private let logger = Logger(subsystem: Log.subsystem, category: "controller")
    @ObservationIgnored private let transport = HIDTransport.logitechBluetooth()
    @ObservationIgnored private let eventTap = EventTapService()
    @ObservationIgnored private let batteryNotifier = BatteryNotifier()
    @ObservationIgnored private var session: Session?
    @ObservationIgnored private var configureTask: Task<Void, Never>?
    @ObservationIgnored private var observers: [any NSObjectProtocol] = []
    @ObservationIgnored private var started = false

    private static let batteryPollInterval: Duration = .seconds(300)
    private static let configureDebounce: Duration = .milliseconds(300)

    // MARK: - Lifecycle

    func start() {
        guard !started else { return }
        started = true

        if !settings.didInitialLoginItemSetup {
            settings.didInitialLoginItemSetup = true
            setLaunchAtLogin(true)
        }

        Permission.inputMonitoring.requestIfUndetermined()
        if settings.backForwardEnabled { Permission.accessibility.requestIfUndetermined() }

        let transport = self.transport
        transport.onMatched = { [weak self] connection in
            // Transport queue: wire up input before any report can be missed, then hop to the main actor.
            let info = connection.info
            guard let profile = SupportedDevices.profile(vendorID: info.vendorID, productID: info.productID, productName: info.product) else {
                return
            }
            let channel = HIDPPChannel(deviceIndex: HIDPP.bluetoothDeviceIndex) { try connection.send($0) }
            transport.setInputHandler({ channel.receive($0) }, for: connection)
            Task { @MainActor in self?.deviceMatched(info: info, profile: profile, channel: channel) }
        }
        transport.onRemoved = { [weak self] info in
            Task { @MainActor in self?.deviceRemoved(info) }
        }
        startTransport()
        observeSystem()
        updateEventTap()
    }

    private func startTransport() {
        switch transport.start() {
        case .ok:
            needsRelaunch = false
            if session == nil { connection = .notFound }
        case .notPermitted:
            connection = .permissionRequired
            needsRelaunch = Permission.inputMonitoring.isGranted
        case .failed(let code):
            connection = .failed(String(format: "HID manager error 0x%08X", UInt32(bitPattern: code)))
        }
    }

    private func observeSystem() {
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.logger.info("Woke from sleep; re-applying settings")
                self.refreshPermissions()
                if self.session != nil { self.scheduleConfigure(after: .seconds(1)) }
            }
        })

        let distributed = DistributedNotificationCenter.default()
        // System Settings › Mouse/Trackpad "Natural scrolling" changed.
        observers.append(distributed.addObserver(forName: .init("SwipeScrollDirectionDidChangeNotification"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                Task { await self.applyScroll() }
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
        if accessibilityChanged { updateEventTap() }
        if inputMonitoring, connection == .permissionRequired { startTransport() }
        launchAtLogin = LoginItem.isEnabled
        launchAtLoginNeedsApproval = LoginItem.needsApproval
    }

    // MARK: - Device events

    private func deviceMatched(info: HIDDeviceInfo, profile: DeviceProfile, channel: HIDPPChannel) {
        session?.close()
        let session = Session(info: info, profile: profile, channel: channel)
        self.session = session
        deviceName = profile.name
        connection = .connected
        session.listener = Task { [weak self] in
            for await message in channel.notifications {
                self?.handleNotification(message, session: session)
            }
        }
        scheduleConfigure(after: Self.configureDebounce)
    }

    private func deviceRemoved(_ info: HIDDeviceInfo) {
        guard let session, session.info.registryID == info.registryID else { return }
        session.close()
        self.session = nil
        configureTask?.cancel()
        connection = .notFound
        battery = nil
        currentDPI = nil
        scrollFallbackActive = false
        updateEventTap()
    }

    /// Debounced: a flurry of matches/wakes results in a single discovery + apply pass.
    private func scheduleConfigure(after delay: Duration) {
        configureTask?.cancel()
        configureTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.configure()
        }
    }

    private func configure() async {
        guard let session else { return }
        let channel = session.channel
        let started = ContinuousClock.now
        do {
            // The link can take a moment to accept HID++ traffic after (re)connecting.
            var version: RootFeature.ProtocolVersion?
            for attempt in 1...3 {
                do {
                    version = try await RootFeature(channel: channel).ping()
                    break
                } catch {
                    if attempt == 3 { throw error }
                    try await Task.sleep(for: .milliseconds(400))
                }
            }
            logger.info("HID++ \(version?.major ?? 0).\(version?.minor ?? 0) on \(session.profile.name, privacy: .public)")

            let found = try await discoverFeatures(
                [.unifiedBattery, .hiResWheel, .thumbwheel, .adjustableDPI, .reprogControlsV4, .wirelessDeviceStatus],
                channel: channel
            )
            try Task.checkCancellation()
            guard self.session === session else { return }
            let features = Features(found, channel: channel)
            session.features = features
            logger.info("Features: \(found.map { "\($0.key)@\($0.value.index)" }.sorted().joined(separator: " "), privacy: .public)")

            if let reprog = features.reprog {
                let controls = try? await reprog.controls()
                session.gestureCID = controls.flatMap { SupportedDevices.gestureButton(in: $0, profile: session.profile) }
            }
            gestureButtonAvailable = session.gestureCID != nil
            if let dpi = features.dpi {
                supportedDPIs = (try? await dpi.supportedDPIs()) ?? []
            }

            await applyAll()
            await refreshBattery()
            startBatteryPoll(for: session)
            lastError = nil
            logger.info("Configured in \(ContinuousClock.now - started, privacy: .public)")
        } catch {
            // Superseded by a newer configure pass or a reconnect.
            guard !Task.isCancelled, self.session === session else { return }
            logger.error("Configure failed: \(String(describing: error), privacy: .public)")
            lastError = String(describing: error)
        }
    }

    private func handleNotification(_ message: HIDPPMessage, session: Session) {
        guard self.session === session, let features = session.features, message.functionID == 0 else { return }
        switch message.featureIndex {
        case features.battery?.index:
            if let status = BatteryFeature.parseStatus(message.params) { setBattery(status) }

        case features.reprog?.index:
            guard let cid = session.gestureCID else { return }
            let pressed = ReprogControlsFeature.pressedControls(inEvent: message.params).contains(cid)
            if pressed, !session.gesturePressed, settings.gestureMissionControl {
                SystemActions.openMissionControl()
            }
            session.gesturePressed = pressed

        case features.wirelessStatusIndex:
            if WirelessDeviceStatus.needsReconfiguration(event: message.params) {
                logger.info("Device requested reconfiguration")
                scheduleConfigure(after: Self.configureDebounce)
            }

        default:
            break
        }
    }

    // MARK: - Applying settings

    private func applyAll() async {
        await applyScroll()
        await applyThumbwheel()
        await applyDPI()
        await applyGesture()
    }

    private func applyScroll() async {
        guard let session, let features = session.features else {
            scrollFallbackActive = false
            updateEventTap()
            return
        }
        let invert = ScrollDirectionPolicy.deviceInvert(
            mouseNatural: settings.mouseScrollDirection == .natural,
            systemNatural: SettingsStore.systemNaturalScrolling
        )
        var appliedOnDevice = false
        if let wheel = features.wheel {
            do {
                appliedOnDevice = try await wheel.setInverted(invert)
            } catch {
                logger.error("Hi-res wheel invert failed: \(String(describing: error), privacy: .public)")
            }
        }
        guard self.session === session else { return }
        // Fall back to the event tap only if the device can't invert and inversion is needed.
        scrollFallbackActive = invert && !appliedOnDevice
        updateEventTap()
    }

    private func applyThumbwheel() async {
        guard let thumb = session?.features?.thumb else { return }
        do {
            try await thumb.setInverted(settings.thumbWheelInverted)
        } catch {
            logger.error("Thumbwheel invert failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func applyDPI() async {
        guard let dpiFeature = session?.features?.dpi else { return }
        do {
            if let wanted = settings.dpi, let dpi = AdjustableDPIFeature.snap(wanted, to: supportedDPIs) {
                try await dpiFeature.setDPI(dpi)
                currentDPI = dpi
            } else {
                currentDPI = try await dpiFeature.currentDPI().current
            }
        } catch {
            logger.error("DPI failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func applyGesture() async {
        guard let session, let reprog = session.features?.reprog, let cid = session.gestureCID else { return }
        do {
            try await reprog.setDiverted(settings.gestureMissionControl, cid: cid)
        } catch {
            logger.error("Gesture button divert failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func updateEventTap() {
        let configuration = EventTapService.Configuration(
            backForward: settings.backForwardEnabled,
            invertScroll: scrollFallbackActive
        )
        if !eventTap.update(configuration) {
            logger.notice("Event tap unavailable until Accessibility is granted")
        }
    }

    // MARK: - Battery

    private func refreshBattery() async {
        guard let feature = session?.features?.battery else { return }
        do {
            setBattery(try await feature.status())
        } catch {
            logger.error("Battery read failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func setBattery(_ status: BatteryStatus) {
        battery = status
        batteryNotifier.update(status, deviceName: deviceName ?? "Mouse", threshold: settings.lowBatteryThreshold)
    }

    private func startBatteryPoll(for session: Session) {
        session.batteryPoll?.cancel()
        session.batteryPoll = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.batteryPollInterval)
                guard !Task.isCancelled else { return }
                await self?.refreshBattery()
            }
        }
    }

    // MARK: - UI actions

    func setScrollDirection(_ direction: SettingsStore.ScrollDirection) {
        settings.mouseScrollDirection = direction
        Task { await applyScroll() }
    }

    func setThumbWheelInverted(_ inverted: Bool) {
        settings.thumbWheelInverted = inverted
        Task { await applyThumbwheel() }
    }

    func setDPI(_ dpi: Int) {
        settings.dpi = dpi
        Task { await applyDPI() }
    }

    func setBackForward(_ enabled: Bool) {
        settings.backForwardEnabled = enabled
        if enabled { Permission.accessibility.requestIfUndetermined() }
        updateEventTap()
    }

    func setGestureMissionControl(_ enabled: Bool) {
        settings.gestureMissionControl = enabled
        Task { await applyGesture() }
    }

    func setShowBatteryInMenuBar(_ show: Bool) {
        settings.showBatteryInMenuBar = show
    }

    func setLowBatteryThreshold(_ threshold: Int) {
        settings.lowBatteryThreshold = threshold
        if threshold > 0 { batteryNotifier.requestAuthorization() }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LoginItem.setEnabled(enabled)
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

// MARK: - Session

/// Everything tied to one connection of the device. Replaced on every match.
@MainActor
private final class Session {
    let info: HIDDeviceInfo
    let profile: DeviceProfile
    let channel: HIDPPChannel
    var features: Features?
    var gestureCID: UInt16?
    var gesturePressed = false
    var listener: Task<Void, Never>?
    var batteryPoll: Task<Void, Never>?

    init(info: HIDDeviceInfo, profile: DeviceProfile, channel: HIDPPChannel) {
        self.info = info
        self.profile = profile
        self.channel = channel
    }

    func close() {
        listener?.cancel()
        batteryPoll?.cancel()
        channel.close()
    }
}

/// Feature handles bound to their runtime indexes for one connection.
private struct Features {
    let battery: BatteryFeature?
    let wheel: HiResWheelFeature?
    let thumb: ThumbwheelFeature?
    let dpi: AdjustableDPIFeature?
    let reprog: ReprogControlsFeature?
    let wirelessStatusIndex: UInt8?

    init(_ found: [FeatureID: FeatureInfo], channel: HIDPPChannel) {
        battery = found[.unifiedBattery].map { BatteryFeature(index: $0.index, channel: channel) }
        wheel = found[.hiResWheel].map { HiResWheelFeature(index: $0.index, channel: channel) }
        thumb = found[.thumbwheel].map { ThumbwheelFeature(index: $0.index, channel: channel) }
        dpi = found[.adjustableDPI].map { AdjustableDPIFeature(index: $0.index, channel: channel) }
        reprog = found[.reprogControlsV4].map { ReprogControlsFeature(index: $0.index, channel: channel) }
        wirelessStatusIndex = found[.wirelessDeviceStatus]?.index
    }
}
