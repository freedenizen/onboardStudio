import Foundation
import Testing

@testable import ProjectModel

/// #75's chain for the speed unit: **object → project → app → the data**, each level deferring
/// unless somebody pinned it.
@Suite("Speed unit inheritance")
struct SpeedUnitInheritanceTests {
    @Test("Each level answers only when the ones below it defer")
    func resolvesInOrder() {
        // Nothing pinned anywhere and no data: the unit every object silently asserted before any
        // of this existed, so a project with nothing loaded looks the way it always did.
        #expect(UnitResolver().speed(.automatic) == .mph)

        // The data is the top of the chain, not a last resort: a file recorded in kph shows kph.
        let recorded = UnitResolver(automatic: .kph)
        #expect(recorded.speed(.automatic) == .kph)

        // The app pins it, so the file's own unit stops mattering.
        var app = recorded
        app.app = .metersPerSecond
        #expect(app.speed(.automatic) == .metersPerSecond)

        // The project pins it, so the app's choice stops mattering.
        var project = app
        project.project = .mph
        #expect(project.speed(.automatic) == .mph)

        // And the object beats everything, which is what it has always done.
        #expect(project.speed(.kph) == .kph)
    }

    @Test("Where the answer came from, so a control can say")
    func reportsTheLevel() {
        #expect(UnitResolver().source(.kph) == .object)
        #expect(UnitResolver(project: .kph).source(.automatic) == .project)
        #expect(UnitResolver(app: .kph).source(.automatic) == .app)
        #expect(UnitResolver(automatic: .kph).source(.automatic) == .data)
        #expect(UnitResolver().source(.automatic) == .fallback)
        // The object level is the only one with nothing to inherit from.
        #expect(UnitSource.object.describedAsInherited == nil)
        #expect(UnitSource.project.describedAsInherited != nil)
    }

    @Test("Changing a level moves everything under it that has not been pinned")
    func changingALevelMovesTheUnpinned() {
        // The consequence the issue calls out as intended rather than a side effect.
        let pinned = SpeedUnitSetting.kph
        let inheriting = SpeedUnitSetting.automatic
        var resolver = UnitResolver(app: .mph)
        #expect(resolver.speed(inheriting) == .mph)
        #expect(resolver.speed(pinned) == .kph)
        resolver.app = .metersPerSecond
        #expect(resolver.speed(inheriting) == .metersPerSecond, "an inheriting object follows")
        #expect(resolver.speed(pinned) == .kph, "a pinned object does not")
    }

    // MARK: - Opening a saved project does not change how it renders

    @Test("An object saved before the chain keeps the unit it was saved with")
    func anOlderObjectKeepsItsUnit() throws {
        // Every build that has had `speedUnit` writes the key, so an absent one can only come from
        // a build older than the field — and every object such a build made asserted mph.
        // Minimal JSON per type: some require their channel, none of them write a unit.
        let speed = Data(#"{"channel":"speed"}"#.utf8)
        #expect(try JSONDecoder().decode(GaugeParams.self, from: speed).speedUnit == .mph)
        #expect(try JSONDecoder().decode(BarParams.self, from: speed).speedUnit == .mph)
        #expect(try JSONDecoder().decode(TextDataParams.self, from: speed).speedUnit == .mph)
        #expect(try JSONDecoder().decode(GraphParams.self, from: Data("{}".utf8)).speedUnit == .mph)
        #expect(try JSONDecoder().decode(LapPanelParams.self, from: Data("{}".utf8)).speedUnit == .mph)

        // The fallback is not the memberwise default and must not be rewritten to follow it.
        #expect(GaugeParams.speedometer().speedUnit == .automatic)
        #expect(BarParams(channel: "speed").speedUnit == .automatic)

        // A file saved by a build that had the field keeps whatever it chose, including the
        // choice that is no longer the default.
        for setting in SpeedUnitSetting.allCases {
            var params = GaugeParams.speedometer()
            params.speedUnit = setting
            let round = try JSONDecoder().decode(GaugeParams.self, from: JSONEncoder().encode(params))
            #expect(round.speedUnit == setting)
        }
    }

    @Test("A project saved before the chain has no project-level opinion")
    func anOlderProjectDefersWithoutChangingAnything() throws {
        let settings = try JSONDecoder().decode(ProjectSettings.self, from: Data(#"{"frameRate":25}"#.utf8))
        #expect(settings.speedUnit == .automatic)
        #expect(settings.frameRate == 25)
        // Which changes nothing, because every object in such a project pins its own unit.
        let resolver = UnitResolver(project: settings.speedUnit, automatic: .kph)
        #expect(resolver.speed(.mph) == .mph, "the object's own pinned unit still wins")
    }

    // MARK: - The two types stay in step

    @Test("The stored setting and the drawn unit agree on their names")
    func rawValuesMatchTheConcreteUnit() {
        // The raw values have to match or an existing file decodes to the wrong case.
        for unit in SpeedDisplayUnit.allCases {
            #expect(SpeedUnitSetting(unit).rawValue == unit.rawValue)
            #expect(SpeedUnitSetting(unit).pinned == unit)
        }
        #expect(SpeedUnitSetting.automatic.pinned == nil)
        // And every concrete setting maps to a unit, so the chain can never run out of cases.
        for setting in SpeedUnitSetting.allCases where setting != .automatic {
            #expect(setting.pinned != nil, "\(setting)")
        }
    }
}
