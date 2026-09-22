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
