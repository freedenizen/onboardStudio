import ProjectModel
import Testing

@testable import RenderKit

/// #699: what the planner hands a dial's and a bar's renderer when the unit drawn is not the one
/// the scale's numbers are in — the app's unit changed in Settings, with no edit of the project.
@Suite("A speed's scale is drawn in the unit shown (#699)")
struct SpeedScaleDrawnTests {
    func project(dial: GaugeParams, bar: BarParams) -> (Project, InputID) {
        let data = Input(label: "d", source: MediaReference(path: "x.csv"), kind: .data(DataInputSettings()))
        let objects = [
            DisplayObject(label: "Speed", inputID: data.id, frame: .full, kind: .speedometer(dial)),
            DisplayObject(label: "Bar", inputID: data.id, frame: .full, kind: .bar(bar)),
        ]
        return (Project(inputs: [data], displayObjects: objects), data.id)
    }

    func drawn(_ project: Project, _ data: InputID, app: SpeedUnitSetting) -> (GaugeParams?, BarParams?) {
        let overlays = RenderPlanner.overlays(
            for: project, sessions: [data: SyntheticSession.session], appSpeedUnit: app)
        let dial = overlays.compactMap { ($0 as? GaugeRenderer)?.params }.first
        let bar = overlays.compactMap { ($0 as? BarRenderer)?.params }.first
        return (dial, bar)
    }

    @Test("A scale in mph is drawn 0–240 when the app's unit is km/h, and as written in mph")
    func theAppsUnitChanges() {
        var dial = GaugeParams(channel: "speed", title: "", minValue: 0, maxValue: 140, majorTick: 20, minorTick: 10)
        dial.scaleUnit = .mph
        var bar = BarParams(channel: "speed", label: "", minValue: 0, maxValue: 140)
        bar.scaleUnit = .mph
        let (project, data) = project(dial: dial, bar: bar)

        let (kphDial, kphBar) = drawn(project, data, app: .kph)
        #expect(kphDial.map { [$0.minValue, $0.maxValue, $0.majorTick, $0.minorTick] } == [0, 240, 20, 10])
        #expect(kphBar.map { [$0.minValue, $0.maxValue] } == [0, 240])

        let (mphDial, mphBar) = drawn(project, data, app: .mph)
        #expect(mphDial == dial && mphBar == bar)
    }

    @Test("A scale with no unit — every project saved before — is drawn as written in any unit")
    func scalesWithNoUnit() {
        let dial = GaugeParams(channel: "speed", title: "", minValue: 0, maxValue: 140, majorTick: 20, minorTick: 10)
        let bar = BarParams(channel: "speed", label: "", minValue: 0, maxValue: 140)
        let (project, data) = project(dial: dial, bar: bar)
        for unit in [SpeedUnitSetting.kph, .mph] {
            let (drawnDial, drawnBar) = drawn(project, data, app: unit)
            #expect(drawnDial == dial && drawnBar == bar, "\(unit)")
        }
    }
}
