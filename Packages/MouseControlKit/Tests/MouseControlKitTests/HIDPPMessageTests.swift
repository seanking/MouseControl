import Testing
@testable import MouseControlKit

@Suite struct HIDPPMessageTests {
    @Test func buildsLongRequest() {
        let m = HIDPPMessage.longRequest(deviceIndex: 0xFF, featureIndex: 0, function: 0, softwareID: 1, params: [0x10, 0x04])
        #expect(m.bytes == Fixture.getFeatureBatteryRequest)
        #expect(m.bytes.count == HIDPP.longReportLength)
    }

    @Test func parsesLongReport() throws {
        let m = try #require(HIDPPMessage(bytes: Fixture.getFeatureBatteryResponse))
        #expect(m.reportID == 0x11)
        #expect(m.deviceIndex == 0xFF)
        #expect(m.featureIndex == 0)
        #expect(m.functionID == 0)
        #expect(m.softwareID == 1)
        #expect(m.params.count == 16)
        #expect(m.params[0] == 0x08)
        #expect(m.bytes == Fixture.getFeatureBatteryResponse)
    }

    @Test func parsesShortReport() throws {
        let m = try #require(HIDPPMessage(bytes: Fixture.bytes("10 01 8F 00 12 05 00")))
        #expect(m.functionByte == 0x00)
        #expect(m.params == [0x12, 0x05, 0x00])
        #expect(m.isHIDPP10Error)
        #expect(!m.isHIDPP20Error)
    }

    @Test func rejectsNonHIDPPAndTruncatedReports() {
        #expect(HIDPPMessage(bytes: Fixture.mouseMovement) == nil)
        #expect(HIDPPMessage(bytes: Fixture.bytes("11 FF 00 01")) == nil)
        #expect(HIDPPMessage(bytes: [UInt8]()) == nil)
    }

    @Test func identifiesHIDPP20Error() throws {
        let m = try #require(HIDPPMessage(bytes: Fixture.errorInvalidFunction))
        #expect(m.isHIDPP20Error)
    }

    @Test func truncatesOversizedParams() {
        let m = HIDPPMessage.longRequest(deviceIndex: 1, featureIndex: 2, function: 3, softwareID: 4, params: Array(repeating: 0xAA, count: 30))
        #expect(m.bytes.count == 20)
        #expect(m.functionByte == 0x34)
    }

    @Test func readsBigEndianU16() {
        let m = HIDPPMessage(reportID: 0x11, deviceIndex: 0xFF, featureIndex: 1, functionByte: 0x21, params: [0, 0x06, 0x40])
        #expect(m.u16(at: 1) == 1600)
        #expect(m.u16(at: 2) == 0)
    }

    @Test func serializesShortReportAtShortLength() {
        let m = HIDPPMessage(reportID: HIDPP.shortReportID, deviceIndex: 0x01, featureIndex: 0x81, functionByte: 0x02, params: [0x05])
        #expect(m.bytes == Fixture.bytes("10 01 81 02 05 00 00"))
        #expect(m.bytes.count == HIDPP.shortReportLength)
    }

    @Test func describesAsHex() {
        let m = HIDPPMessage(reportID: HIDPP.shortReportID, deviceIndex: 0xFF, featureIndex: 0x0A, functionByte: 0x1F, params: [0xAB])
        #expect(m.description == "10 FF 0A 1F AB 00 00")
    }
}

@Suite struct HIDPPErrorTests {
    @Test(arguments: [
        (HIDPPError.device(code: 7), "HID++ error invalidFunctionID (7)"),
        (.device(code: 0x42), "HID++ error 66"),
        (.hidpp10(code: 9), "HID++ 1.0 error 9"),
        (.timeout, "Device did not respond"),
        (.sendFailed(-536_870_212), "Report send failed (0xE00002BC)"),
        (.featureNotSupported(.thumbwheel), "Feature 0x2150 not supported"),
        (.malformedResponse, "Malformed response"),
        (.disconnected, "Device disconnected"),
    ])
    func describesErrors(error: HIDPPError, description: String) {
        #expect(error.description == description)
    }

    @Test func formatsFeatureIDAsHex() {
        #expect(FeatureID.reprogControlsV4.description == "0x1B04")
        #expect(FeatureID.root.description == "0x0000")
    }
}
