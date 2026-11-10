import Foundation
import TelemetryKit
import Testing

@testable import ProjectModel

/// #464: with nothing chosen, a RaceChrono project's speedometer read metres per second, the
/// Logbook read km/h whatever the setting, and Coaching read km/h unless the setting said mph.
/// One rule now: a unit somebody chose, else the file's own mph or km/h, else the region's.
@Suite("The region's speed unit (#464)")
struct RegionalSpeedUnitTests {
    static let american = Locale(identifier: "en_US")
    static let british = Locale(identifier: "en_GB")
    static let german = Locale(identifier: "de_DE")

    @Test func aRegionReadsTheUnitItsRoadsAreSignedIn() {
        #expect(SpeedDisplayUnit.regional(Self.american) == .mph)
        #expect(SpeedDisplayUnit.regional(Self.british) == .mph, "miles on the road, whatever the shop scales say")
        #expect(SpeedDisplayUnit.regional(Self.german) == .kph)
        #expect(SpeedDisplayUnit.regional(Locale(identifier: "fr_CA")) == .kph)
        #expect(SpeedDisplayUnit.regional(Locale(identifier: "ja_JP")) == .kph)
    }

    @Test func aFileInMetresPerSecondIsShownInTheRegionsUnit() {
        // RaceChrono's CSV records m/s. Nobody reads a speedometer in it.
        let german = UnitResolver(automatic: .metersPerSecond, regional: .kph)
        #expect(german.speed(.automatic) == .kph)
        #expect(german.source(.automatic) == .region)
        #expect(UnitSource.region.describedAsInherited == "for your region, as the data is in m/s")
        #expect(UnitResolver(automatic: .metersPerSecond, regional: .mph).speed(.automatic) == .mph)

        // A file that recorded a road unit is still shown in it, wherever it is opened.
        let recorded = UnitResolver(automatic: .mph, regional: .kph)
        #expect(recorded.speed(.automatic) == .mph)
        #expect(recorded.source(.automatic) == .data)

        // No data to ask: the last resort it always was, not the region.
        #expect(UnitResolver(regional: .kph).speed(.automatic) == .mph)
        #expect(UnitResolver(regional: .kph).source(.automatic) == .fallback)
    }

    @Test func metresPerSecondIsStillThereForWhoeverChoosesIt() {
        var resolver = UnitResolver(automatic: .metersPerSecond, regional: .mph)
        #expect(resolver.speed(.metersPerSecond) == .metersPerSecond, "the object's own choice")
        resolver.app = .metersPerSecond
        #expect(resolver.speed(.automatic) == .metersPerSecond, "Settings ▸ Units ▸ Speed")
        #expect(resolver.source(.automatic) == .app)
        resolver.project = .kph
        #expect(resolver.speed(.automatic) == .kph)
    }

    @Test func withoutARegionTheFilesUnitStands() {
        // What a project saved before schema 3 is given, and what the planner does when its caller
        // names no region.
        let resolver = UnitResolver(automatic: .metersPerSecond)
        #expect(resolver.speed(.automatic) == .metersPerSecond)
        #expect(resolver.source(.automatic) == .data)
    }

    @Test func aWindowWithNoFileToAskFollowsTheSettingThenTheRegion() {
        #expect(SpeedUnitSetting.automatic.shown(in: Self.american) == .mph)
        #expect(SpeedUnitSetting.automatic.shown(in: Self.german) == .kph)
        #expect(SpeedUnitSetting.mph.shown(in: Self.german) == .mph)
        #expect(SpeedUnitSetting.kph.shown(in: Self.american) == .kph)
        #expect(SpeedUnitSetting.metersPerSecond.shown(in: Self.american) == .metersPerSecond)
    }

    @Test func aSpeedIsWrittenInTheUnitWithItsSymbol() {
        #expect(SpeedDisplayUnit.kph.text(metersPerSecond: 50) == "180 km/h")
        #expect(SpeedDisplayUnit.mph.text(metersPerSecond: 50) == "112 mph")
        #expect(SpeedDisplayUnit.metersPerSecond.text(metersPerSecond: 50) == "50 m/s")
        #expect(SpeedDisplayUnit.kph.changeText(metersPerSecond: 1) == "+4 km/h")
        #expect(SpeedDisplayUnit.mph.changeText(metersPerSecond: -1) == "-2 mph")
        #expect(SpeedDisplayUnit.mph.changeText(metersPerSecond: 0.1) == "same")
    }

    @Test func coachingIsWrittenInTheSameUnits() {
        #expect(CoachingUnits.following(.mph, locale: Self.german) == .imperial)
        #expect(CoachingUnits.following(.kph, locale: Self.american) == .metric)
        #expect(CoachingUnits.following(.metersPerSecond, locale: Self.american) == .metric)
        #expect(CoachingUnits.following(.automatic, locale: Self.american) == .imperial)
        #expect(CoachingUnits.following(.automatic, locale: Self.german) == .metric)
        // A project saved before schema 3: metric unless the app says mph, as that build wrote it.
        #expect(CoachingUnits.following(.automatic, legacyAutomatic: true, locale: Self.american) == .metric)
        #expect(CoachingUnits.following(.mph, legacyAutomatic: true, locale: Self.german) == .imperial)
    }

    // MARK: - Saved projects

    /// `data` as a build at `version` wrote it: without the key schema 3 added.
    func saved(before data: Data, version: Int) throws -> Data {
        var root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        var settings = try #require(root["settings"] as? [String: Any])
        settings["legacyAutomaticUnits"] = nil
        root["settings"] = settings
        root["schemaVersion"] = version
        return try JSONSerialization.data(withJSONObject: root)
    }

    @Test func aProjectSavedBeforeKeepsWhatAutomaticMeantThen() throws {
        let old = try saved(before: try Project().encoded(), version: 2)
        let opened = try Project.decode(old)
        #expect(opened.schemaVersion == Project.currentSchemaVersion)
        #expect(opened.settings.legacyAutomaticUnits, "the migration states what that build did")
        // And it stays stated once saved again.
        #expect(try Project.decode(try opened.encoded()).settings.legacyAutomaticUnits)
    }

    @Test func aProjectMadeSinceFollowsTheRegion() throws {
        let project = Project()
        #expect(!project.settings.legacyAutomaticUnits)
        // Always written, so absence can only mean "saved before the field existed".
        let json = try #require(String(data: try project.encoded(), encoding: .utf8))
        #expect(json.contains("\"legacyAutomaticUnits\" : false"))
        #expect(try !Project.decode(try project.encoded()).settings.legacyAutomaticUnits)
    }

    /// The checked-in project, saved long before the change, opens pinned to the old meaning.
    @Test func theFixtureProjectKeepsItsUnits() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/slice.onboardproj/project.json")
        let project = try Project.decode(try Data(contentsOf: url))
        #expect(project.settings.legacyAutomaticUnits)
        #expect(project.schemaVersion == Project.currentSchemaVersion)
    }
}
