import ProjectModel
import TelemetryKit
import Testing

@testable import RenderKit

/// *Automatic* at the top of the speed unit chain means "what the file recorded". The builder
/// converts every speed channel to m/s on import, so the planner must ask the session for the
/// recorded unit, not the channel — reading the channel answered m/s for every file ever loaded.
@Suite("Recorded speed unit")
struct RecordedSpeedUnitTests {
    func session(speedUnit: TelemetryUnit?) -> TelemetrySession {
        var columns = [RawColumn(name: "Ignored", values: [1, 2, 3, 4])]
        if let speedUnit {
            columns.insert(
                RawColumn(name: "Speed", unit: speedUnit, suggestedRole: .speed, values: [36, 72, 108, 144]), at: 0)
        }
        return SessionBuilder.build(
            RawTable(info: SessionInfo(sourceFormat: "test"), times: [0, 1, 2, 3], columns: columns))
    }

    @Test("A built session answers with the unit the file recorded")
    func recordedUnitSurvivesCanonicalisation() {
        #expect(session(speedUnit: .kilometersPerHour)[.speed]?.unit == .metersPerSecond)
        #expect(RenderPlanner.recordedSpeedUnit(of: session(speedUnit: .kilometersPerHour)) == .kph)
        #expect(RenderPlanner.recordedSpeedUnit(of: session(speedUnit: .milesPerHour)) == .mph)
        #expect(RenderPlanner.recordedSpeedUnit(of: session(speedUnit: .metersPerSecond)) == .metersPerSecond)
    }

    @Test("A unit the app cannot show, or no speed at all, has no opinion")
    func unknownUnitsDefer() {
        #expect(RenderPlanner.recordedSpeedUnit(of: session(speedUnit: .custom("knots"))) == nil)
        #expect(RenderPlanner.recordedSpeedUnit(of: session(speedUnit: nil)) == nil)
    }

    @Test("Every level deferring lands on the recorded unit, then on mph without one")
    func automaticResolvesToTheData() {
        let kph = UnitResolver(
            app: .automatic, project: .automatic,
            automatic: RenderPlanner.recordedSpeedUnit(of: session(speedUnit: .kilometersPerHour)))
        #expect(kph.speed(.automatic) == .kph)
        #expect(kph.source(.automatic) == .data)
        let none = UnitResolver(
            app: .automatic, project: .automatic,
            automatic: RenderPlanner.recordedSpeedUnit(of: session(speedUnit: nil)))
        #expect(none.speed(.automatic) == .mph)
        #expect(none.source(.automatic) == .fallback)
    }

    /// A speedometer on `project`, reading a session recorded in `unit`, as the planner resolves it.
    func resolver(_ project: Project, recorded unit: TelemetryUnit, regional: SpeedDisplayUnit?) -> UnitResolver {
        let inputID = InputID()
        var project = project
        project.inputs = [
            Input(
                id: inputID, label: "data", source: MediaReference(path: "x.csv"), kind: .data(DataInputSettings()))
        ]
        let object = DisplayObject(
            label: "Speed", inputID: inputID, frame: UnitRect(x: 0, y: 0, width: 1, height: 1),
            kind: .speedometer(.speedometer()))
        return RenderPlanner.unitResolver(
            for: object, in: project, sessions: [inputID: session(speedUnit: unit)], appSpeedUnit: .automatic,
            regionalSpeedUnit: regional)
    }

    @Test("A file in m/s is shown in the region's unit, and one in a road unit in its own (#464)")
    func metresPerSecondGivesWayToTheRegion() {
        let made = resolver(Project(), recorded: .metersPerSecond, regional: .kph)
        #expect(made.speed(.automatic) == .kph)
        #expect(made.source(.automatic) == .region)
        #expect(resolver(Project(), recorded: .metersPerSecond, regional: .mph).speed(.automatic) == .mph)
        #expect(resolver(Project(), recorded: .milesPerHour, regional: .kph).speed(.automatic) == .mph)
        // A caller that names no region gets the file's unit, as the planner always answered.
        #expect(resolver(Project(), recorded: .metersPerSecond, regional: nil).speed(.automatic) == .metersPerSecond)
    }

    @Test("A project saved before schema 3 goes on showing what its file recorded (#464)")
    func aSavedProjectKeepsMetresPerSecond() throws {
        var saved = Project()
        saved.settings.legacyAutomaticUnits = true
        let resolved = resolver(saved, recorded: .metersPerSecond, regional: .mph)
        #expect(resolved.speed(.automatic) == .metersPerSecond)
        #expect(resolved.source(.automatic) == .data)
    }
}
