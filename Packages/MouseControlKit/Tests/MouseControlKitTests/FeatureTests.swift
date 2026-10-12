import Testing
@testable import MouseControlKit

@Suite struct RootFeatureTests {
    @Test func parsesGetFeature() {
        #expect(RootFeature.parseGetFeature([0x0A, 0x00, 0x01], for: .hiResWheel) == FeatureInfo(index: 0x0A, type: 0, version: 1))
        #expect(RootFeature.parseGetFeature([0x00, 0x00, 0x00], for: .thumbwheel) == nil)
        #expect(RootFeature.parseGetFeature([0x00, 0x00, 0x02], for: .root) != nil)
    }

    @Test func discoversOnlyPresentFeatures() async throws {
        let table: [UInt16: UInt8] = [0x1004: 0x08, 0x2121: 0x0A, 0x2201: 0x0C]
        let device = FixtureDevice { call in
            let id = UInt16(call.params[0]) << 8 | UInt16(call.params[1])
            if id == 0x1B04 { throw HIDPPError.device(code: 2) }
            return [table[id] ?? 0, 0, 0]
        }
        let found = try await discoverFeatures([.unifiedBattery, .hiResWheel, .thumbwheel, .reprogControlsV4, .adjustableDPI], channel: device)
        #expect(found.mapValues(\.index) == [.unifiedBattery: 0x08, .hiResWheel: 0x0A, .adjustableDPI: 0x0C])
    }

    @Test func pingReturnsProtocolVersion() async throws {
        let device = FixtureDevice { call in [4, 5, call.params[2]] }
        let version = try await RootFeature(channel: device).ping()
        #expect(version == .init(major: 4, minor: 5))
    }
}

@Suite struct BatteryFeatureTests {
    @Test func parsesDischarging() throws {
        let s = try #require(BatteryFeature.parseStatus([0x55, 0x04, 0x00, 0x00]))
        #expect(s == BatteryStatus(percentage: 85, level: .good, charging: .discharging, externalPower: false))
    }

    @Test func parsesChargingStates() {
        #expect(BatteryFeature.parseStatus([50, 0x04, 1, 1])?.charging == .charging)
        #expect(BatteryFeature.parseStatus([50, 0x04, 2, 1])?.charging == .chargingSlow)
        #expect(BatteryFeature.parseStatus([100, 0x08, 3, 1])?.charging == .full)
        #expect(BatteryFeature.parseStatus([50, 0x04, 4, 1])?.charging == .error)
        #expect(BatteryFeature.parseStatus([50, 0x04, 1, 1])?.charging.isCharging == true)
    }

    @Test func approximatesWithoutStateOfCharge() {
        #expect(BatteryFeature.parseStatus([0, 0x02, 0, 0])?.percentage == 20)
        #expect(BatteryFeature.parseStatus([0, 0x01, 0, 0])?.level == .critical)
    }

    @Test func rejectsShortPayload() {
        #expect(BatteryFeature.parseStatus([0x55]) == nil)
    }

    @Test func readsStatusWithFunction1() async throws {
        let device = FixtureDevice { _ in [0x0A, 0x01, 0x00, 0x00] }
        let status = try await BatteryFeature(index: 8, channel: device).status()
        #expect(status.percentage == 10)
        #expect(device.calls == [.init(featureIndex: 8, function: 1, params: [])])
    }
}

@Suite struct HiResWheelTests {
    @Test func computesModeKeepingResolutionAndClearingDivert() {
        typealias M = HiResWheelFeature.Mode
        #expect(HiResWheelFeature.mode(from: [.highResolution, .diverted], inverted: true) == [.highResolution, .inverted])
        #expect(HiResWheelFeature.mode(from: [.inverted], inverted: false) == [])
    }

    @Test func setInvertedReadsModifiesWritesAndVerifies() async throws {
        let device = FixtureDevice { call in
            switch call.function {
            case 1: [0x06]          // read-back: hi-res + inverted
            case 2: call.params     // echo
            default: []
            }
        }
        let ok = try await HiResWheelFeature(index: 0x0A, channel: device).setInverted(true)
        #expect(ok)
        #expect(device.calls.map(\.function) == [1, 2, 1])
        #expect(device.calls[1].params == [0x06])
    }

    @Test func reportsWhenDeviceIgnoresInvert() async throws {
        let device = FixtureDevice { call in call.function == 1 ? [0x00] : [] }
        let ok = try await HiResWheelFeature(index: 0x0A, channel: device).setInverted(true)
        #expect(!ok)
    }

    @Test(arguments: [
        (true, true, false), (false, true, true), (true, false, true), (false, false, false),
    ])
    func scrollPolicy(mouseNatural: Bool, systemNatural: Bool, invert: Bool) {
        #expect(ScrollDirectionPolicy.deviceInvert(mouseNatural: mouseNatural, systemNatural: systemNatural) == invert)
    }
}

@Suite struct ThumbwheelTests {
    @Test func parsesStatus() {
        #expect(ThumbwheelFeature.parseStatus([0, 1, 0, 0]) == .init(diverted: false, inverted: true))
        #expect(ThumbwheelFeature.parseStatus([1, 0]) == .init(diverted: true, inverted: false))
    }

    @Test func setInvertedUsesFunction2NativeReporting() async throws {
        let device = FixtureDevice { $0.params }
        try await ThumbwheelFeature(index: 0x0D, channel: device).setInverted(true)
        #expect(device.calls == [.init(featureIndex: 0x0D, function: 2, params: [0, 1])])
    }
}

@Suite struct AdjustableDPITests {
    @Test func expandsStepRange() {
        // sensor 0: 200, step 50 (0xE032), 8000, terminator
        let list = AdjustableDPIFeature.parseDPIList([0x00, 0x00, 0xC8, 0xE0, 0x32, 0x1F, 0x40, 0x00, 0x00])
        #expect(list.first == 200)
        #expect(list.last == 8000)
        #expect(list.count == (8000 - 200) / 50 + 1)
        #expect(list.contains(1600))
        #expect(!list.contains(1625))
    }

    @Test func parsesExplicitList() {
        let list = AdjustableDPIFeature.parseDPIList([0x00, 0x01, 0x90, 0x03, 0x20, 0x06, 0x40, 0x00, 0x00, 0x0C, 0x80])
        #expect(list == [400, 800, 1600])
    }

    @Test func parsesMixedListAndRange() {
        // 400, 800..1600 step 400, 3200
        let list = AdjustableDPIFeature.parseDPIList([0x00, 0x01, 0x90, 0x03, 0x20, 0xE1, 0x90, 0x06, 0x40, 0x0C, 0x80, 0x00, 0x00])
        #expect(list == [400, 800, 1200, 1600, 3200])
    }

    @Test func readsCurrentAndSets() async throws {
        let device = FixtureDevice { call in
            call.function == 2 ? [0x00, 0x06, 0x40, 0x03, 0xE8] : call.params
        }
        let feature = AdjustableDPIFeature(index: 0x0C, channel: device)
        let (current, def) = try await feature.currentDPI()
        #expect(current == 1600)
        #expect(def == 1000)
        try await feature.setDPI(4000)
        #expect(device.calls.last == .init(featureIndex: 0x0C, function: 3, params: [0x00, 0x0F, 0xA0]))
    }

    @Test func snapsToNearestSupported() {
        let supported = [200, 250, 300, 1000]
        #expect(AdjustableDPIFeature.snap(270, to: supported) == 250)
        #expect(AdjustableDPIFeature.snap(275, to: supported) == 250)
        #expect(AdjustableDPIFeature.snap(9000, to: supported) == 1000)
        #expect(AdjustableDPIFeature.snap(100, to: []) == nil)
    }
}

@Suite struct ReprogControlsTests {
    // CID 0x00C3 (gesture), TID 0x00D7, flags 0x30 (reprogrammable|divertable), additional flags 0x01
    static let gestureInfo: [UInt8] = [0x00, 0xC3, 0x00, 0xD7, 0x30, 0x00, 0x03, 0x00, 0x01]
    // CID 0x0050 (left button), not divertable
    static let leftInfo: [UInt8] = [0x00, 0x50, 0x00, 0x38, 0x01, 0x01, 0x01, 0x00, 0x00]

    @Test func parsesControlInfo() {
        let c = ReprogControlsFeature.parseControl(Self.gestureInfo)
        #expect(c.cid == 0x00C3)
        #expect(c.taskID == 0x00D7)
        #expect(c.flags == 0x0130)
        #expect(c.isDivertable)
        #expect(!ReprogControlsFeature.parseControl(Self.leftInfo).isDivertable)
    }

    @Test func enumeratesControlsAndFindsGestureButton() async throws {
        let device = FixtureDevice { call in
            switch call.function {
            case 0: [2]
            case 1: call.params[0] == 0 ? ReprogControlsTests.leftInfo : ReprogControlsTests.gestureInfo
            default: []
            }
        }
        let controls = try await ReprogControlsFeature(index: 0x09, channel: device).controls()
        #expect(controls.map(\.cid) == [0x0050, 0x00C3])
        #expect(SupportedDevices.gestureButton(in: controls, profile: SupportedDevices.mxMaster3S) == 0x00C3)
        #expect(SupportedDevices.gestureButton(in: [controls[0]], profile: SupportedDevices.mxMaster3S) == nil)
    }

    @Test func divertParams() {
        #expect(ReprogControlsFeature.reportingParams(cid: 0x00C3, diverted: true) == [0x00, 0xC3, 0x03, 0x00, 0x00])
        #expect(ReprogControlsFeature.reportingParams(cid: 0x00C3, diverted: false) == [0x00, 0xC3, 0x02, 0x00, 0x00])
    }

    @Test func parsesDivertedButtonEvents() {
        #expect(ReprogControlsFeature.pressedControls(inEvent: [0x00, 0xC3] + Array(repeating: 0, count: 14)) == [0x00C3])
        #expect(ReprogControlsFeature.pressedControls(inEvent: Array(repeating: 0, count: 16)).isEmpty)
        #expect(ReprogControlsFeature.pressedControls(inEvent: [0x00, 0xC3, 0x00, 0xC4, 0, 0, 0, 0]) == [0x00C3, 0x00C4])
    }

    @Test func wirelessStatusReconfiguration() {
        #expect(WirelessDeviceStatus.needsReconfiguration(event: [1, 1, 0]))
        #expect(WirelessDeviceStatus.needsReconfiguration(event: [0, 1, 0]))
        #expect(!WirelessDeviceStatus.needsReconfiguration(event: [0, 0, 0]))
    }
}

@Suite struct SupportedDevicesTests {
    @Test func matchesMXMaster3S() {
        #expect(SupportedDevices.profile(vendorID: 0x046D, productID: 0xB034, productName: nil) == SupportedDevices.mxMaster3S)
        #expect(SupportedDevices.profile(vendorID: 0x046D, productID: 0xB999, productName: "MX Master 3S B") == SupportedDevices.mxMaster3S)
        #expect(SupportedDevices.profile(vendorID: 0x046D, productID: 0xB023, productName: "MX Master 3") == nil)
        #expect(SupportedDevices.profile(vendorID: 0x05AC, productID: 0xB034, productName: nil) == nil)
    }
}

@Suite struct DeviceNameTests {
    @Test func readsNameAcrossChunks() async throws {
        let name = Array("MX Master 3S".utf8)
        let device = FixtureDevice { call in
            if call.function == 0 { return [UInt8(name.count)] }
            // Hand out 8 characters per call to exercise chunking.
            let start = Int(call.params[0])
            return Array(name[start..<min(start + 8, name.count)])
        }
        let feature = DeviceNameFeature(index: 0x03, channel: device)
        #expect(try await feature.name() == "MX Master 3S")
        #expect(device.calls.map(\.params.first) == [nil, 0, 8])
    }

    @Test func matchesReceiverDevicesByName() {
        #expect(SupportedDevices.profile(named: "MX Master 3S") == SupportedDevices.mxMaster3S)
        #expect(SupportedDevices.profile(named: "MX Keys S") == nil)
        #expect(SupportedDevices.isReceiver(vendorID: 0x046D, productID: 0xC548))
        #expect(!SupportedDevices.isReceiver(vendorID: 0x046D, productID: 0xB034))
    }
}
