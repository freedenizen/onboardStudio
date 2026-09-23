import Testing

@testable import TelemetryKit

/// The attribute window's filter field and the Import tab's wording (#200).
@Suite("Attribute filter and report wording")
struct AttributeFilterTests {
    @Test func anEmptyFilterMatchesEverything() {
        #expect(ChannelRole.speed.matches(filter: ""))
        #expect(ChannelRole.speed.matches(filter: "   "))
    }

    /// Matched anywhere in the name, whatever the case: "pressure" finds both brake pressures.
    @Test func matchesTheDisplayNameAnywhereIgnoringCase() {
        #expect(ChannelRole.brakePressureFront.matches(filter: "PRESSURE"))
        #expect(ChannelRole.brakePressureFront.matches(filter: "front"))
        #expect(!ChannelRole.speed.matches(filter: "pressure"))
    }

    @Test func ignoresAccents() {
        #expect(ChannelRole.coolantTemperature.matches(filter: "tempé"))
    }

    /// The column an attribute is read from is as good a handle as its name: a user who knows the
    /// logger calls it `analog_2` types that.
    @Test func matchesTheSourceColumn() {
        #expect(ChannelRole.brake.matches(filter: "analog_2", source: "analog_2"))
        #expect(!ChannelRole.brake.matches(filter: "analog_2", source: nil))
    }

    @Test func aVocabularyAttributeIsDescribedByItsName() {
        let column = ImportReport.Column(id: 0, name: "Brake press", unit: .kilopascal, role: .brakePressureFront)
        #expect(column.becameDescription == "Brake pressure (front) · kPa")
    }

    @Test func aUnitlessAttributeIsDescribedByItsNameAlone() {
        let column = ImportReport.Column(id: 0, name: "Gear", role: .gear)
        #expect(column.becameDescription == "Gear")
    }

    /// A channel the file named itself is not described by the codebase's `canbus:…` identifier.
    @Test func aFileOwnChannelIsNotDescribedByItsIdentifier() {
        let column = ImportReport.Column(id: 0, name: "66569", role: .canbus("66569"))
        #expect(column.becameDescription == "Kept as its own channel")
        #expect(!column.becameDescription.contains("canbus"))
    }

    @Test func anUnimportedColumnSaysSo() {
        #expect(ImportReport.Column(id: 0, name: "junk").becameDescription == "Not imported")
    }

    @Test func aReportColumnMatchesByNameSourceOrWhatItBecame() {
        let column = ImportReport.Column(
            id: 0, name: "Brake press", source: "200: canbus", unit: .kilopascal, role: .brakePressureFront)
        #expect(column.matches(filter: "press"))
        #expect(column.matches(filter: "canbus"))
        #expect(column.matches(filter: "front"))
        #expect(!column.matches(filter: "throttle"))
    }
}
