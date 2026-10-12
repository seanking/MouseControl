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
}
