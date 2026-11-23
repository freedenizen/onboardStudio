import Foundation
import Testing

@testable import ProjectModel

/// #668: a dial fitted to its file as 0–160 mph and then set to km/h was still 0–160. The readout
/// converted, and the needle sat past the end of the dial for most of the lap.
@Suite("A speed's scale follows a change of unit (#668)")
struct SpeedScaleUnitsTests {
    /// A file whose speed, stored in metres per second, runs from standstill to `top`.
    func file(top: Double) -> [ChannelSummary] {
        [ChannelSummary(identifier: "speed", name: "Speed", unit: "m/s", minValue: 0, maxValue: top)]
    }

    func scale(_ params: GaugeParams) -> [Double] {
        [params.minValue, params.maxValue, params.majorTick, params.minorTick]
    }

    @Test func aDialStillAsItsFileFittedItIsFittedAgainInTheNewUnit() {
        // 58 m/s is about 130 mph, 209 km/h.
        let mph = GaugeParams.speedometer().fitted(to: file(top: 58), speedUnit: .mph)
        #expect(scale(mph) == [0, 160, 20, 10])
        let kph = mph.reshown(from: .mph, in: .kph, channels: file(top: 58))
        #expect(scale(kph) == [0, 240, 20, 10], "the dial a speedometer in km/h has for this file")
        #expect(kph.maxValue > 58 * 3.6, "the needle has room at the top speed")
        // And back: exactly the dial it was.
        #expect(kph.reshown(from: .kph, in: .mph, channels: file(top: 58)) == mph)
        #expect(scale(mph.reshown(from: .mph, in: .metersPerSecond, channels: file(top: 58))) == [0, 65, 5, 2.5])
    }

    @Test func aDialSetByHandShowsTheSameSpeedsInTheNewUnit() {
        var chosen = GaugeParams.speedometer().fitted(to: file(top: 58), speedUnit: .mph)
        (chosen.maxValue, chosen.majorTick, chosen.minorTick) = (200, 25, 5)
        let kph = chosen.reshown(from: .mph, in: .kph, channels: file(top: 58))
        // 200 mph is 322 km/h: the dial reaches it, ends on a label, and its labels are round.
        #expect(scale(kph) == [0, 350, 50, 25])
        #expect(kph.maxValue >= 200 * 1.609_344)
        // With no file loaded there is nothing to compare with, and the scale is converted too.
        let fitted = GaugeParams.speedometer().fitted(to: file(top: 58), speedUnit: .mph)
        #expect(scale(fitted.reshown(from: .mph, in: .kph, channels: [])) == [0, 260, 20, 10])
    }

    @Test func zonesAreSpeedsAndConvertWithTheScale() throws {
        var zoned = GaugeParams.speedometer().fitted(to: file(top: 58), speedUnit: .mph)
        zoned.zones = [GaugeZone(from: 100, to: 120, color: .red), GaugeZone(from: 120, to: nil, color: .red)]
        let kph = zoned.reshown(from: .mph, in: .kph, channels: file(top: 58))
        #expect(scale(kph) == [0, 260, 20, 10], "converted, not fitted again: its zones say it was drawn by hand")
        let first = try #require(kph.zones.first)
        #expect(abs(first.from - 160.934) < 0.01 && abs((first.to ?? 0) - 193.121) < 0.01)
        #expect(kph.zones.last?.to == nil, "to the maximum stays to the maximum")
        #expect(kph.zones.map(\.id) == zoned.zones.map(\.id))
    }

    @Test func whatIsNoSpeedOrStillWaitsForItsFileIsLeftAlone() {
        let tacho = GaugeParams.tachometer()
        #expect(tacho.reshown(from: .mph, in: .kph, channels: file(top: 58)) == tacho)
        // The preset dial is fitted when its first file arrives, in whatever unit it has by then.
        let waiting = GaugeParams.speedometer()
        #expect(waiting.reshown(from: .mph, in: .kph, channels: []) == waiting)
        let fitted = waiting.fitted(to: file(top: 58), speedUnit: .mph)
        #expect(fitted.reshown(from: .mph, in: .mph, channels: file(top: 58)) == fitted, "the same unit")
    }

    @Test func aBarOfSpeedFollowsItsUnitToo() {
        let mph = BarParams(channel: "speed").fitted(to: file(top: 58), speedUnit: .mph)
        let kph = mph.reshown(from: .mph, in: .kph, channels: file(top: 58))
        #expect(kph.minValue == 0 && kph.maxValue == 240)
        #expect(kph.reshown(from: .kph, in: .mph, channels: file(top: 58)) == mph)
        var chosen = mph
        chosen.maxValue = 100
        #expect(chosen.reshown(from: .mph, in: .kph, channels: file(top: 58)).maxValue == 180, "100 mph and a little")
        let throttle = BarParams(channel: "throttle")
        #expect(throttle.reshown(from: .mph, in: .kph, channels: file(top: 58)) == throttle)
    }

    // MARK: - In a project

    @Test func onlyTheObjectsWhoseUnitChangedAreRedrawn() throws {
        let input = Input(label: "data", source: MediaReference(path: "x.csv"), kind: .data(DataInputSettings()))
        let fitted = GaugeParams.speedometer().fitted(to: file(top: 58), speedUnit: .mph)
        let speed = DisplayObject(label: "Speed", inputID: input.id, frame: .full, kind: .speedometer(fitted))
        let other = DisplayObject(label: "Other", inputID: input.id, frame: .full, kind: .speedometer(fitted))
        let revs = DisplayObject(label: "RPM", inputID: input.id, frame: .full, kind: .tachometer(.tachometer()))
        var project = Project(inputs: [input], displayObjects: [speed, other, revs])
        #expect(project.speedScaleObjects.map(\.label) == ["Speed", "Other"])

        let shown = [speed.id: SpeedDisplayUnit.mph, other.id: .mph]
        // "Speed" was set to km/h; "Other" still shows mph.
        let changed = project.reshowSpeedScales(from: shown, channels: [input.id: file(top: 58)]) { object in
            object.id == speed.id ? .kph : .mph
        }
        #expect(changed == ["Speed"])
        #expect(project.displayObjects[0].kind.gaugeParams.map(scale) == [0, 240, 20, 10])
        #expect(project.displayObjects[1] == other && project.displayObjects[2] == revs)

        // An object the edit itself made is not in `shown`, and is left as it was made.
        var made = Project(inputs: [input], displayObjects: [speed])
        #expect(made.reshowSpeedScales(from: [:], channels: [input.id: file(top: 58)]) { _ in .kph }.isEmpty)
        #expect(made.displayObjects == [speed])
    }
}
