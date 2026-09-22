import Foundation
import Testing

@testable import ProjectModel

@Suite("Attribute mapping")
struct AttributeMappingTests {
    /// The milestone's example, spread across the levels it is meant to be settable at.
    let resolver = AttributeMappingResolver(
        global: AttributeMappingTable([
            "brake": AttributeMapping(source: "canbus:front_brake_pressure", sourceUnit: "kPa", displayUnit: "bar")
        ]),
        project: AttributeMappingTable(["brake": AttributeMapping(displayUnit: "psi")]),
        input: AttributeMappingTable(["brake": AttributeMapping(source: "Brake press")]))

    @Test func eachFieldResolvesOnItsOwn() {
        let brake = resolver.resolved("brake")
        #expect(brake.source == "Brake press")  // the input's word
        #expect(brake.sourceUnit == "kPa")  // nobody below overrode the global
        #expect(brake.displayUnit == "psi")  // the project's word, not the global's
    }

    @Test func reportsWhichLevelAnswered() {
        #expect(resolver.level(of: .source, for: "brake") == .input)
        #expect(resolver.level(of: .sourceUnit, for: "brake") == .global)
        #expect(resolver.level(of: .displayUnit, for: "brake") == .project)
        #expect(resolver.level(of: .source, for: "speed") == .automatic)
    }

    @Test func anAttributeNobodyTouchedIsAutomatic() {
        let throttle = resolver.resolved("throttle")
        #expect(throttle.isAutomatic)
        #expect(throttle.source == nil)
    }

    @Test func mappedRolesIsTheUnionOfEveryLevel() {
        var resolver = resolver
        resolver.project["speed"] = AttributeMapping(displayUnit: "mph")
        #expect(resolver.mappedRoles == ["brake", "speed"])
    }

    /// An empty resolver must not invent opinions — this is what every existing project has.
    @Test func anEmptyResolverSaysNothing() {
        let empty = AttributeMappingResolver()
        #expect(empty.mappedRoles.isEmpty)
        #expect(empty.resolved("speed").isAutomatic)
        #expect(empty.level(of: .displayUnit, for: "speed") == .automatic)
    }

    /// What a control at one level edits, and what it would fall back to if cleared.
    @Test func eachLevelIsReadableOnItsOwn() {
        #expect(resolver[.input]["brake"].source == "Brake press")
        #expect(resolver[.input]["brake"].displayUnit == nil)
        #expect(resolver[.project]["brake"].displayUnit == "psi")
        #expect(resolver[.global]["brake"].sourceUnit == "kPa")
        #expect(resolver[.automatic]["brake"].isAutomatic)
    }

    @Test func inheritedIsWhatClearingALevelWouldLeave() {
        let below = resolver.inherited("brake", below: .input)
        #expect(below.source == "canbus:front_brake_pressure")  // the global's, the project is silent
        #expect(below.displayUnit == "psi")  // the project's

        #expect(resolver.inherited("brake", below: .project).displayUnit == "bar")
        #expect(resolver.inherited("brake", below: .global).isAutomatic)
    }

    /// Clearing a field really does produce what `inherited` promised.
    @Test func clearingAFieldFallsBackToWhatWasPromised() {
        var resolver = resolver
        let promised = resolver.inherited("brake", below: .input)
        resolver[.input]["brake"] = AttributeMapping()
        #expect(resolver.resolved("brake") == promised)
    }

    @Test func writingThroughALevelSticks() {
        var resolver = AttributeMappingResolver()
        resolver[.global]["speed"] = AttributeMapping(displayUnit: "kph")
        #expect(resolver.resolved("speed").displayUnit == "kph")
        #expect(resolver.level(of: .displayUnit, for: "speed") == .global)
    }

    @Test func clearingEveryFieldRemovesTheRow() {
        var table = AttributeMappingTable(["speed": AttributeMapping(displayUnit: "mph")])
        #expect(table.rows.count == 1)
        table["speed"] = AttributeMapping()
        #expect(table.isEmpty)
        #expect(AttributeMappingTable(["speed": AttributeMapping()]).isEmpty)
    }

    @Test func tableRoundTripsThroughJSONText() {
        let table = AttributeMappingTable(["brake": AttributeMapping(sourceUnit: "kPa", displayUnit: "bar")])
        #expect(AttributeMappingTable(json: table.json) == table)
        #expect(AttributeMappingTable().json.isEmpty)
        #expect(AttributeMappingTable(json: "").isEmpty)
        #expect(AttributeMappingTable(json: "{ not json").isEmpty)
    }

    /// Encoded as the bare dictionary, so the saved document reads the way a person would write it.
    @Test func tableEncodesAsItsRows() throws {
        let table = AttributeMappingTable(["brake": AttributeMapping(displayUnit: "bar")])
        let json = try JSONSerialization.jsonObject(with: try JSONEncoder().encode(table))
        let rows = try #require(json as? [String: [String: String]])
        #expect(rows == ["brake": ["displayUnit": "bar"]])
    }
}

@Suite("Attribute mapping and the document")
struct AttributeMappingDocumentTests {
    /// A project saved before the table existed has no key for it, and must read as "no opinion" —
    /// which is what it did, since only `roleOverrides` and `unitOverrides` spoke back then.
    @Test func aDocumentWithoutTheKeyDecodesAsAutomatic() throws {
        let settings = try JSONDecoder().decode(
            DataInputSettings.self, from: Data(#"{"roleOverrides":{"Brake press":"brake"}}"#.utf8))
        #expect(settings.attributeMappings.isEmpty)
        #expect(settings.roleOverrides == ["Brake press": "brake"])

        let project = try JSONDecoder().decode(ProjectSettings.self, from: Data(#"{"frameRate":60}"#.utf8))
        #expect(project.attributeMappings.isEmpty)
        #expect(project.frameRate == 60)
    }

    @Test func theTableSurvivesASaveAndReopen() throws {
        var settings = DataInputSettings()
        settings.attributeMappings["brake"] = AttributeMapping(source: "Brake press", sourceUnit: "kPa")
        var project = ProjectSettings()
        project.attributeMappings["speed"] = AttributeMapping(displayUnit: "kph")

        let reopened = try JSONDecoder().decode(
            DataInputSettings.self, from: try JSONEncoder().encode(settings))
        #expect(reopened.attributeMappings["brake"].source == "Brake press")
        #expect(reopened.attributeMappings["brake"].sourceUnit == "kPa")
        #expect(reopened.attributeMappings["brake"].displayUnit == nil)

        let reopenedProject = try JSONDecoder().decode(ProjectSettings.self, from: try JSONEncoder().encode(project))
        #expect(reopenedProject.attributeMappings["speed"].displayUnit == "kph")
    }
}

@Suite("An object's own display unit")
struct ObjectDisplayUnitTests {
    /// Absent in every project saved before this existed, and `nil` is what such an object did:
    /// follow the levels above it. So there is nothing for a schema step to pin.
    @Test func anObjectWithoutTheKeyFollowsTheLevelsAboveIt() throws {
        let json =
            #"{"id":"11111111-1111-1111-1111-111111111111","label":"B","frame":"#
            + #"{"x":0,"y":0,"width":1,"height":1},"opacity":1,"isVisible":true,"#
            + #""kind":{"gear":{"_0":{}}}}"#
        let object = try JSONDecoder().decode(DisplayObject.self, from: Data(json.utf8))
        #expect(object.displayUnit == nil)
    }

    @Test func theUnitSurvivesASaveAndReopen() throws {
        var object = DisplayObject(
            label: "Brake", inputID: nil, frame: UnitRect(x: 0, y: 0, width: 1, height: 1),
            kind: .bar(BarParams(channel: "canbus:brake", label: "B")))
        object.displayUnit = "bar"
        let reopened = try JSONDecoder().decode(DisplayObject.self, from: try JSONEncoder().encode(object))
        #expect(reopened.displayUnit == "bar")
    }

    /// Which channels an object-level unit reaches: the ones it draws a number for. A light and a
    /// steering wheel read a channel but draw no number, so neither has a unit to choose.
    @Test func onlyObjectsThatDrawANumberHaveChannels() {
        #expect(DisplayObjectKind.bar(BarParams(channel: "brake", label: "B")).displayChannels == ["brake"])
        #expect(DisplayObjectKind.gauge(GaugeParams.speedometer()).displayChannels == ["speed"])
        #expect(
            DisplayObjectKind.graph(GraphParams(series: [GraphSeries(channel: "speed")], label: "G"))
                .displayChannels == ["speed"])
        #expect(DisplayObjectKind.lapPanel(LapPanelParams()).displayChannels == ["speed", "speedDelta"])
        #expect(DisplayObjectKind.indicator(.abs).displayChannels.isEmpty)
        #expect(DisplayObjectKind.steeringWheel(SteeringWheelParams()).displayChannels.isEmpty)
        #expect(DisplayObjectKind.gear(GearParams()).displayChannels.isEmpty)
    }
}

@Suite("A state attribute's threshold")
struct AttributeThresholdTests {
    /// A state has no unit to be shown in; what it needs is the level its channel counts as on at.
    @Test func aThresholdResolvesThroughTheChainLikeAnyOtherField() {
        let resolver = AttributeMappingResolver(
            global: AttributeMappingTable(["absActive": AttributeMapping(source: "analog_1", threshold: 1500)]),
            project: AttributeMappingTable(["absActive": AttributeMapping(threshold: 2000)]))
        #expect(resolver.resolved("absActive").threshold == 2000)
        #expect(resolver.resolved("absActive").source == "analog_1", "field by field, as ever")
        #expect(resolver.inherited("absActive", below: .project).threshold == 1500)
    }

    /// A row with only a threshold is still a row; it must not be dropped as "says nothing".
    @Test func aThresholdAloneIsAnOpinion() throws {
        var table = AttributeMappingTable()
        table["absActive"] = AttributeMapping(threshold: 1500)
        #expect(!table.isEmpty)
        #expect(!table["absActive"].isAutomatic)
        let reopened = try JSONDecoder().decode(AttributeMappingTable.self, from: try JSONEncoder().encode(table))
        #expect(reopened["absActive"].threshold == 1500)
    }

    /// Absent in every project saved before states existed, and absent means automatic.
    @Test func anOlderRowHasNoThreshold() throws {
        let table = try JSONDecoder().decode(
            AttributeMappingTable.self, from: Data(#"{"brake":{"sourceUnit":"kPa"}}"#.utf8))
        #expect(table["brake"].threshold == nil)
        #expect(table["brake"].sourceUnit == "kPa")
    }
}
