import Testing

@testable import TelemetryKit

/// What the inspector's channel pickers call a channel (#208).
@Suite("Channel picker titles")
struct ChannelPickerTitleTests {
    @Test func anAttributeIsNamedAsTheAttributeTableNamesIt() {
        #expect(ChannelRole.lateralG.pickerTitle == "Lateral G")
        #expect(ChannelRole.pickerTitle(forIdentifier: "brakePressureFront") == "Brake pressure (front)")
    }

    /// A file's own channel keeps its name, and says where it came from, so `Speed` off the CAN
    /// bus is not read as the Speed attribute.
    @Test func aFileOwnChannelKeepsItsNameAndSaysWhereFrom() {
        #expect(ChannelRole.canbus("Speed").pickerTitle == "Speed (CAN bus)")
        #expect(ChannelRole.obd("Coolant").pickerTitle == "Coolant (OBD)")
        #expect(ChannelRole.aux("analog_1").pickerTitle == "analog_1")
        #expect(ChannelRole.pickerTitle(forIdentifier: "canbus:analog_1") == "analog_1 (CAN bus)")
    }

    @Test func anUnknownIdentifierIsShownAsItIs() {
        #expect(ChannelRole.pickerTitle(forIdentifier: "").isEmpty)
        #expect(ChannelRole.pickerTitle(forIdentifier: "notAThing:x") == "notAThing:x")
    }
}
