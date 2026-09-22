import ProjectModel
import TelemetryKit
import Testing

@testable import RenderKit

/// #89: every attribute is drawn in the unit the chain resolves for it, not only speed.
@Suite("Display units")
struct DisplayUnitTests {
    static let inputID = InputID()

    /// A file shaped like the milestone's example: brake logged in kPa on a CAN channel, and a
    /// speed column in km/h, which the builder canonicalises to m/s.
    func session() -> TelemetrySession {
        SessionBuilder.build(
            RawTable(
                info: SessionInfo(sourceFormat: "test"), times: [0, 1],
                columns: [
                    RawColumn(
                        name: "Speed", unit: .kilometersPerHour, suggestedRole: .speed, values: [36, 72]),
                    RawColumn(
                        name: "front_brake_pressure", unit: .kilopascal,
                        suggestedRole: .canbus("front_brake_pressure"), values: [100, 200]),
                ]))
    }

    func project(
        projectMappings: AttributeMappingTable = AttributeMappingTable(),
        inputMappings: AttributeMappingTable = AttributeMappingTable(),
        speedUnit: SpeedUnitSetting = .automatic
    ) -> Project {
        var settings = DataInputSettings()
        settings.attributeMappings = inputMappings
        var project = Project()
        project.settings.attributeMappings = projectMappings
        project.settings.speedUnit = speedUnit
        project.inputs = [
            Input(id: Self.inputID, label: "data", source: MediaReference(path: "x.csv"), kind: .data(settings))
        ]
        return project
    }

    func object(_ kind: DisplayObjectKind) -> DisplayObject {
        DisplayObject(label: "o", inputID: Self.inputID, frame: UnitRect(x: 0, y: 0, width: 1, height: 1), kind: kind)
    }

    func units(
        _ project: Project, object: DisplayObject? = nil,
        global: AttributeMappingTable = AttributeMappingTable()
    ) -> DisplayUnits {
        RenderPlanner.displayUnits(
            for: object ?? self.object(.bar(BarParams(channel: "canbus:front_brake_pressure", label: "B"))),
            in: project, sessions: [Self.inputID: session()], appSpeedUnit: .automatic,
            globalAttributeMappings: global)
    }

    /// The statement this milestone is accepted against, through the renderer's own seam.
    @Test func brakeInKilopascalsIsShownInBar() {
        let table = AttributeMappingTable([
            "canbus:front_brake_pressure": AttributeMapping(sourceUnit: "kPa", displayUnit: "bar")
        ])
        let units = units(project(projectMappings: table))
        #expect(units.value(100, of: "canbus:front_brake_pressure") == 1)
        #expect(units.label(for: "canbus:front_brake_pressure") == "bar")
    }

    /// The trap: speed is *stored* in m/s however the file wrote it, so a conversion that started
    /// from the recorded km/h would apply the 3.6 twice. 10 m/s is 22.37 mph, not 80.5.
    @Test func speedConvertsFromWhatIsStoredNotFromWhatTheFileWrote() throws {
        let table = AttributeMappingTable(["speed": AttributeMapping(displayUnit: "mph")])
        let units = units(project(projectMappings: table))
        #expect(session().recordedUnit(of: .speed) == .kilometersPerHour, "the file's unit is still remembered")
        #expect(try #require(session()[.speed]).unit == .metersPerSecond, "but the values are stored in m/s")
        #expect(abs(units.value(10, of: "speed") - 22.369_362) < 1e-5)
    }

    /// An attribute nobody gave a display unit is drawn exactly as stored, which is what every
    /// project saved before this existed gets.
    @Test func anAttributeWithNoDisplayUnitIsUnchanged() {
        let units = units(project())
        #expect(units.value(100, of: "canbus:front_brake_pressure") == 100)
        #expect(units.label(for: "canbus:front_brake_pressure") == nil, "so the object's own label stands")
    }

    // MARK: - Where in the chain the answer came from

    @Test func aMoreSpecificLevelWins() {
        let project = project(
            projectMappings: AttributeMappingTable([
                "canbus:front_brake_pressure": AttributeMapping(displayUnit: "psi")
            ]),
            inputMappings: AttributeMappingTable([
                "canbus:front_brake_pressure": AttributeMapping(displayUnit: "bar")
            ]))
        #expect(units(project).label(for: "canbus:front_brake_pressure") == "bar")
    }

    @Test func theGlobalLevelReachesAnUntouchedProject() {
        let global = AttributeMappingTable([
            "canbus:front_brake_pressure": AttributeMapping(displayUnit: "psi")
        ])
        #expect(units(project(), global: global).label(for: "canbus:front_brake_pressure") == "psi")
    }

    /// An object that pinned its own speed unit still outranks the table, as it always has.
    @Test func anObjectsOwnSpeedUnitOutranksTheTable() {
        let table = AttributeMappingTable(["speed": AttributeMapping(displayUnit: "km/h")])
        let pinned = object(.gauge(GaugeParams.speedometer(unit: .mph)))
        let units = units(project(projectMappings: table), object: pinned)
        #expect(units.label(for: "speed") == "mph")
        #expect(abs(units.value(10, of: "speed") - 22.369_362) < 1e-5)
    }

    /// With nothing pinned anywhere, speed still resolves through #75 — and keeps the spelling it
    /// has always been drawn with. `kph`, not `km/h`: changing it would change every saved
    /// project's speedometer.
    @Test func speedKeepsItsLegacySpellingWhenTheOldChainAnswers() {
        #expect(units(project(speedUnit: .kph)).label(for: "speed") == "kph")
        #expect(units(project()).label(for: "speed") == "kph", "the file recorded km/h")
    }

    /// A unit the values cannot be converted into leaves them alone: a wrong number is worse than
    /// an unconverted one.
    @Test func anImpossibleConversionChangesNothing() {
        let table = AttributeMappingTable([
            "canbus:front_brake_pressure": AttributeMapping(displayUnit: "mph")
        ])
        #expect(units(project(projectMappings: table)).value(100, of: "canbus:front_brake_pressure") == 100)
    }

    /// An object reading an input with no session at all must not crash or invent conversions.
    @Test func noDataMeansNoConversions() {
        let units = RenderPlanner.displayUnits(
            for: object(.bar(BarParams(channel: "speed", label: "S"))), in: project(), sessions: [:],
            appSpeedUnit: .automatic, globalAttributeMappings: AttributeMappingTable())
        #expect(units.value(10, of: "speed") == 10)
        #expect(units.label(for: "speed") == nil)
    }
}
