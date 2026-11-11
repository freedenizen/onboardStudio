import Foundation
import Testing

@testable import ProjectModel

/// #487: a speedometer's dial was 0–160 in every unit. In km/h that is 99 mph, and the needle
/// stopped there on every straight; in m/s a car at 200 km/h never passed a third of the dial.
@Suite("A speed dial in the unit it shows (#487)")
struct SpeedScaleTests {
    /// A file whose speed, stored in metres per second, runs from standstill to `top`.
    func file(top: Double) -> [ChannelSummary] {
        [ChannelSummary(identifier: "speed", name: "Speed", unit: "m/s", minValue: 0, maxValue: top)]
    }

    func scale(_ params: GaugeParams) -> [Double] {
        [params.minValue, params.maxValue, params.majorTick, params.minorTick]
    }

    @Test func theDialIsTheOneASpeedometerInThatUnitWouldHave() {
        // 58 m/s is about 130 mph, 209 km/h.
        let speedo = GaugeParams.speedometer()
        #expect(scale(speedo.fitted(to: file(top: 58), speedUnit: .mph)) == [0, 160, 20, 10])
        #expect(scale(speedo.fitted(to: file(top: 58), speedUnit: .kph)) == [0, 240, 20, 10])
        #expect(scale(speedo.fitted(to: file(top: 58), speedUnit: .metersPerSecond)) == [0, 65, 5, 2.5])
        // The needle has room above the top speed in each.
        for unit in SpeedDisplayUnit.allCases {
            let fitted = speedo.fitted(to: file(top: 58), speedUnit: unit)
            #expect(fitted.maxValue > 58 * unit.factorFromMetersPerSecond)
            #expect(fitted.maxValue.truncatingRemainder(dividingBy: fitted.majorTick) == 0, "ends on a label")
        }
    }

    @Test func theStepBetweenLabelsSuitsTheSpeed() {
        #expect(GaugeParams.speedScale(top: 130) == SpeedScale(max: 160, major: 20, minor: 10))
        #expect(GaugeParams.speedScale(top: 209) == SpeedScale(max: 240, major: 20, minor: 10))
        #expect(GaugeParams.speedScale(top: 330).max == 400, "a very fast car: steps of 50")
        #expect(GaugeParams.speedScale(top: 330).major == 50)
        #expect(GaugeParams.speedScale(top: 45) == SpeedScale(max: 50, major: 5, minor: 2.5), "a kart")
        #expect(GaugeParams.speedScale(top: 0).max > 0, "a file that never moved still gets a dial")
    }

    @Test func aFittedDialNoLongerWaits() {
        let speedo = GaugeParams.speedometer()
        #expect(speedo.scaleAwaitsData)
        #expect(!speedo.fitted(to: file(top: 58), speedUnit: .mph).scaleAwaitsData)
        // A gauge made any other way was never waiting.
        #expect(!GaugeParams.tachometer().scaleAwaitsData)
    }

    @Test func zonesStillPinTheScale() {
        var speedo = GaugeParams.speedometer()
        speedo.zones = [GaugeZone(from: 120, to: nil, color: .red)]
        #expect(scale(speedo.fitted(to: file(top: 58), speedUnit: .kph)) == [0, 160, 20, 10])
    }

    @Test func aBarOfSpeedIsScaledInItsUnitToo() {
        let bar = BarParams(channel: "speed")
        #expect(bar.fitted(to: file(top: 58)) == bar, "no unit, no fit")
        let kph = bar.fitted(to: file(top: 58), speedUnit: .kph)
        #expect(kph.minValue == 0 && kph.maxValue == 240)
        // A difference of speed straddles zero and gets a symmetric scale in the unit.
        let delta = BarParams(channel: "speedDelta").fitted(
            to: [ChannelSummary(identifier: "speedDelta", name: "Δ", unit: "m/s", minValue: -4, maxValue: 6)],
            speedUnit: .kph)
        #expect(delta.minValue == -delta.maxValue && delta.maxValue >= 6 * 3.6)
    }

    // MARK: - A template's dial, when its project first gets data

    func project(_ params: GaugeParams) -> (Project, InputID) {
        let input = Input(label: "data", source: MediaReference(path: "x.csv"), kind: .data(DataInputSettings()))
        let object = DisplayObject(label: "Speed", inputID: input.id, frame: .full, kind: .speedometer(params))
        return (Project(inputs: [input], displayObjects: [object]), input.id)
    }

    func dial(_ project: Project) -> GaugeParams? { project.displayObjects.first?.kind.gaugeParams }

    @Test func aTemplatesSpeedometerIsFittedWhenItsProjectFirstGetsData() throws {
        var (project, input) = project(.speedometer())
        // Before the file has loaded there is nothing to fit to, and the dial goes on waiting.
        #expect(project.fitSpeedScales([:]) { _ in .kph }.isEmpty)
        #expect(dial(project)?.scaleAwaitsData == true)

        #expect(project.fitSpeedScales([input: file(top: 58)]) { _ in .kph } == ["Speed"])
        let fitted = try #require(dial(project))
        #expect(scale(fitted) == [0, 240, 20, 10] && !fitted.scaleAwaitsData)
        // Once: another file later does not move a dial that has been fitted.
        #expect(project.fitSpeedScales([input: file(top: 90)]) { _ in .kph }.isEmpty)
        let later = try #require(dial(project))
        #expect(scale(later) == [0, 240, 20, 10])
    }

    @Test func inMilesPerHourTheDialStaysAsItWasAndSaysNothing() throws {
        var (project, input) = project(.speedometer())
        // 0–160 by 20 is the right dial for this car in mph: nothing is drawn differently.
        #expect(project.fitSpeedScales([input: file(top: 58)]) { _ in .mph }.isEmpty)
        let params = try #require(dial(project))
        #expect(scale(params) == [0, 160, 20, 10] && !params.scaleAwaitsData)
    }

    @Test func aDialChangedByHandIsLeftAlone() throws {
        var chosen = GaugeParams.speedometer()
        chosen.maxValue = 120
        var (project, input) = project(chosen)
        #expect(project.fitSpeedScales([input: file(top: 58)]) { _ in .kph }.isEmpty)
        let params = try #require(dial(project))
        #expect(params.maxValue == 120 && !params.scaleAwaitsData)
    }

    /// A project saved before the field existed: its dial was never waiting, whatever it shows.
    @Test func aSavedProjectsDialIsNotTouched() throws {
        let (made, input) = project(.speedometer())
        var root = try #require(try JSONSerialization.jsonObject(with: try made.encoded()) as? [String: Any])
        func strip(_ value: Any) -> Any {
            if var dictionary = value as? [String: Any] {
                dictionary["scaleAwaitsData"] = nil
                return dictionary.mapValues(strip)
            }
            if let array = value as? [Any] { return array.map(strip) }
            return value
        }
        root = try #require(strip(root) as? [String: Any])
        var opened = try Project.decode(try JSONSerialization.data(withJSONObject: root))
        #expect(dial(opened)?.scaleAwaitsData == false)
        #expect(opened.fitSpeedScales([input: file(top: 58)]) { _ in .kph }.isEmpty)
        let kept = try #require(dial(opened))
        #expect(scale(kept) == [0, 160, 20, 10])
        // A project made now writes the field, so its absence can only mean "saved before".
        let json = try #require(String(data: try made.encoded(), encoding: .utf8))
        #expect(json.contains("\"scaleAwaitsData\" : true"))
    }

    @Test func everyBuiltInTemplatesSpeedometerWaitsForData() {
        let dials = ProjectTemplate.builtIn.flatMap(\.displayObjects).compactMap { object -> GaugeParams? in
            if case .speedometer(let params) = object.kind { return params }
            return nil
        }
        #expect(!dials.isEmpty)
        let waiting = dials.filter { $0.scaleAwaitsData }
        #expect(waiting.count == dials.count)
    }
}
