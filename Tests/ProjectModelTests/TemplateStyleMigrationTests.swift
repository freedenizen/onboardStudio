import Foundation
import Testing

@testable import ProjectModel

/// Templates and object styles carry the same rule projects do: **one applied later renders the
/// way it did when it was saved.** They embed `DisplayObject` and every params type with it, and
/// applying one replaces those wholesale, so a default that moves reaches them by a different door
/// from the one `Project.migrateIfNeeded()` watches (#124).
@Suite("Template and style migration")
struct TemplateStyleMigrationTests {
    static func fixture(_ name: String) throws -> Data {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try Data(contentsOf: root.appending(path: "Tests/Fixtures/\(name)"))
    }

    // MARK: - The seam

    @Test func bothTypesMigrateOnTheWayIn() throws {
        // A file from an older format is brought up to the current one rather than being taken at
        // face value, which is the hook a default change needs in order to pin the old behaviour.
        var old = try ProjectTemplate(data: Self.fixture("fixture.onboardtemplate"))
        old.formatVersion = 0
        try old.migrateIfNeeded()
        #expect(old.formatVersion == ProjectTemplate.formatVersion)

        var style = try ObjectStyle(data: Self.fixture("fixture.onboardstyle"))
        style.formatVersion = 0
        try style.migrateIfNeeded()
        #expect(style.formatVersion == ObjectStyle.formatVersion)
    }

    @Test func aFileFromANewerBuildIsStillRefused() throws {
        // The check that was there before moved inside the migration; it has not been lost.
        var template = try ProjectTemplate(data: Self.fixture("fixture.onboardtemplate"))
        template.formatVersion = ProjectTemplate.formatVersion + 1
        #expect(throws: ProjectTemplateError.self) { try template.migrateIfNeeded() }
        var style = try ObjectStyle(data: Self.fixture("fixture.onboardstyle"))
        style.formatVersion = ObjectStyle.formatVersion + 1
        #expect(throws: ObjectStyleError.self) { try style.migrateIfNeeded() }

        // And still refused through the front door, which is how a user meets it.
        let encoder = JSONEncoder()
        #expect(throws: ProjectTemplateError.self) { try ProjectTemplate(data: encoder.encode(template)) }
        #expect(throws: ObjectStyleError.self) { try ObjectStyle(data: encoder.encode(style)) }
    }

    @Test func decodingGoesThroughTheSeamAndNowhereElse() throws {
        // `init(data:)` is the only way either type is read anywhere in the app or the CLI, so
        // unlike `Project.decode(_:)` there is no second door. A file at the current version comes
        // through it unchanged.
        let template = try ProjectTemplate(data: Self.fixture("fixture.onboardtemplate"))
        #expect(template.formatVersion == ProjectTemplate.formatVersion)
        let style = try ObjectStyle(data: Self.fixture("fixture.onboardstyle"))
        #expect(style.formatVersion == ObjectStyle.formatVersion)
    }

    // MARK: - The fixtures resolve to what they were saved with

    /// The template is a frozen file, not something rebuilt from today's code. **Do not regenerate
    /// it to make this pass.** A failure here means a default moved on a type a template can
    /// carry, and the answer is a migration that pins the old value — which is exactly the moment
    /// #124 was filed for.
    @Test func theTemplateFixtureAppliesTheValuesItWasSavedWith() throws {
        let template = try ProjectTemplate(data: Self.fixture("fixture.onboardtemplate"))
        var project = Project()
        template.apply(to: &project)

        #expect(project.settings.outputWidth == 2560)
        #expect(project.settings.outputHeight == 1440)
        #expect(project.displayObjects.count == 5)

        let map = try #require(project.displayObjects.first { $0.label == "Map" })
        guard case .trackMap(let mapParams) = map.kind else {
            Issue.record("Map is not a track map")
            return
        }
        // Saved before `.trackOnly` became the default for a new map, and still drawing the lap it
        // was saved drawing.
        #expect(mapParams.trace == .referenceLap)
        #expect(mapParams.colorBySector)
        #expect(mapParams.rotation == 37)

        let delta = try #require(project.displayObjects.first { $0.label == "Delta" })
        guard case .timer(let timerParams) = delta.kind else {
            Issue.record("Delta is not a timer")
            return
        }
        #expect(timerParams.mode == .deltaToBest)
        #expect(timerParams.deltaReference == .previousLap)
        #expect(timerParams.decimals == 3)

        let speed = try #require(project.displayObjects.first { $0.label == "Speed" })
        guard case .speedometer(let gauge) = speed.kind else {
            Issue.record("Speed is not a speedometer")
            return
        }
        // The unit is the one #89 would change a default for.
        #expect(gauge.speedUnit == .mph)
        #expect(gauge.maxValue == 180)
        #expect(gauge.title == "SPEED")

        let throttle = try #require(project.displayObjects.first { $0.label == "Throttle" })
        guard case .bar(let barParams) = throttle.kind else {
            Issue.record("Throttle is not a bar")
            return
        }
        #expect(barParams.channel == "throttle")
        #expect(barParams.segments == 20)
        #expect(barParams.fillFromZero)

        // Frames survive applying, or a layout would not be a layout.
        #expect(abs(map.frame.x - 0.72) < 1e-9)
        #expect(abs(map.frame.width - 0.24) < 1e-9)
    }

    /// The same for a style. Frozen for the same reason and not to be regenerated either.
    @Test func theStyleFixtureAppliesTheValuesItWasSavedWith() throws {
        let style = try ObjectStyle(data: Self.fixture("fixture.onboardstyle"))
        var object = DisplayObject(
            label: "Somewhere else", inputID: nil, frame: UnitRect(x: 0.4, y: 0.4, width: 0.1, height: 0.1),
            kind: .trackMap(TrackMapParams()))
        style.apply(to: &object)

        guard case .trackMap(let params) = object.kind else {
            Issue.record("The style did not carry a track map")
            return
        }
        #expect(params.trace == .referenceLap)
        #expect(params.colorBySector)
        #expect(params.rotation == 37)
        #expect(abs(object.opacity - 0.8) < 1e-9)
        #expect(abs(object.frame.width - 0.33) < 1e-9)
        #expect(abs(object.frame.height - 0.44) < 1e-9)
        // A style carries a look and a size, never a position or a label.
        #expect(object.label == "Somewhere else")
        #expect(abs(object.frame.x - 0.4) < 1e-9)
    }

    // MARK: - The case the seam exists for

    @Test func aTemplateSavedBeforeAFieldExistedKeepsTheOldBehaviour() throws {
        // What actually goes wrong without any of this: a template written by a build that had no
        // `trace` key at all. Today the pinned decode fallback catches it — but that carries one
        // bit and works once per key, so the next default change on a template-reachable type has
        // to use the migration instead.
        let json = """
            {"formatVersion":1,"name":"Old","displayObjects":[
              {"id":"11111111-1111-1111-1111-111111111111","label":"Map","frame":
               {"x":0,"y":0,"width":0.2,"height":0.3},"opacity":1,"isVisible":true,
               "kind":{"trackMap":{"_0":{"lineWidth":3}}}}]}
            """
        let template = try ProjectTemplate(data: Data(json.utf8))
        var project = Project()
        template.apply(to: &project)
        guard case .trackMap(let params) = try #require(project.displayObjects.first).kind else {
            Issue.record("not a track map")
            return
        }
        // Drawing every position in the file, as it did before the option existed — not the
        // `.trackOnly` a map created today would get.
        #expect(params.trace == .wholeSession)
        #expect(params.trace != TrackMapParams().trace)
        #expect(params.lineWidth == 3)
    }
}
