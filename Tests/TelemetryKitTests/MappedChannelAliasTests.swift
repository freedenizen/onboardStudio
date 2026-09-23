import Testing

@testable import TelemetryKit

/// #214: a column the user points an attribute at is offered in both forms — as the attribute and
/// under the file's own name — and mapping it leaves every other channel where it was.
@Suite("Mapped channels keep their raw form")
struct MappedChannelAliasTests {
    func table() -> RawTable {
        RawTable(
            info: SessionInfo(sourceFormat: "test"), times: [0, 1, 2],
            columns: [
                RawColumn(
                    name: "brake_pressure_front", unit: .kilopascal,
                    suggestedRole: .canbus("brake_pressure_front"), values: [0, 5000, 14000]),
                RawColumn(
                    name: "steering_angle", unit: .degrees, suggestedRole: .canbus("steering_angle"),
                    values: [0, 10, -10]),
                RawColumn(name: "brake_pos", unit: .percent, suggestedRole: .brake, values: [0, 50, 100]),
            ])
    }

    @Test func aMappedCANColumnIsBothTheAttributeAndItsRawChannel() throws {
        let session = SessionBuilder.build(
            table(), options: .init(sourceColumns: [.brakePressureFront: "brake_pressure_front"]))
        let mapped = try #require(session[.brakePressureFront], "the attribute is missing")
        let raw = try #require(session[.canbus("brake_pressure_front")], "the raw channel is missing")
        #expect(mapped.values == raw.values)
        #expect(mapped.name == raw.name)
    }

    @Test func mappingOneColumnLeavesTheOthersAlone() {
        let plain = SessionBuilder.build(table())
        let mapped = SessionBuilder.build(
            table(), options: .init(sourceColumns: [.brakePressureFront: "brake_pressure_front"]))
        let before = Set(plain.orderedChannels.map(\.role))
        let after = Set(mapped.orderedChannels.map(\.role))
        #expect(before.isSubset(of: after), "mapping lost \(before.subtracting(after))")
        #expect(after.subtracting(before) == [.brakePressureFront])
    }

    /// The column-keyed override is the same request made from the other side.
    @Test func aRoleOverrideKeepsTheRawChannelToo() {
        let session = SessionBuilder.build(
            table(), options: .init(roleOverrides: ["steering_angle": .steeringAngle]))
        #expect(session[.steeringAngle] != nil)
        #expect(session[.canbus("steering_angle")] != nil)
    }

    /// A vocabulary guess the user overrode is the importer's reading, not the column's own
    /// name, so it is not kept alongside: Brake would otherwise stay on a column now mapped to
    /// something else.
    @Test func anOverriddenVocabularyGuessIsNotKept() {
        let session = SessionBuilder.build(table(), options: .init(sourceColumns: [.clutch: "brake_pos"]))
        #expect(session[.clutch] != nil)
        #expect(session[.brake] == nil)
    }
}
