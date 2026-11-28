import Foundation
import Testing

@testable import ProjectModel

/// #699: a speed dial's scale was numbers with no unit, so a dial made 0–140 for mph was 0–140
/// in km/h when the unit was changed in Settings, where no edit of the project could take the
/// scale along. A scale now says what unit its numbers are in, and is converted when drawn.
@Suite("A speed's scale says what unit it is in (#699)")
struct SpeedScaleUnitTests {
    func file(top: Double) -> [ChannelSummary] {
        [ChannelSummary(identifier: "speed", name: "Speed", unit: "m/s", minValue: 0, maxValue: top)]
    }

    func scale(_ params: GaugeParams) -> [Double] {
        [params.minValue, params.maxValue, params.majorTick, params.minorTick]
    }

    /// 58 m/s is about 130 mph: a dial of 0–160 by 20.
    var fitted: GaugeParams { GaugeParams.speedometer().fitted(to: file(top: 58), speedUnit: .mph) }

    @Test("A scale fitted to a file is in the unit it was fitted in")
    func fittedScalesSayTheirUnit() {
        #expect(fitted.scaleUnit == .mph && scale(fitted) == [0, 160, 20, 10])
        #expect(GaugeParams.speedometer().fitted(to: file(top: 58), speedUnit: .kph).scaleUnit == .kph)
        let bar = BarParams(channel: "speed", label: "", minValue: 0, maxValue: 100)
        #expect(bar.fitted(to: file(top: 58), speedUnit: .kph).scaleUnit == .kph)
        // A speedometer still waiting for its file has no scale to speak of yet.
        #expect(GaugeParams.speedometer().scaleUnit == nil)
        // Revs are not a speed.
        let revs = [ChannelSummary(identifier: "rpm", name: "RPM", unit: "rpm", minValue: 900, maxValue: 7200)]
        #expect(GaugeParams.tachometer().fitted(to: revs, speedUnit: .mph).scaleUnit == nil)
    }

    @Test("Drawn in its own unit a scale is itself; in another, the same speeds with round labels")
    func drawnInAnotherUnit() {
        #expect(fitted.drawn(in: .mph) == fitted)
        let kph = fitted.drawn(in: .kph)
        // 160 mph is 257 km/h: the dial reaches it and its labels are round.
        #expect(scale(kph) == [0, 260, 20, 10] && kph.scaleUnit == .kph)
        #expect(kph.maxValue >= 160 * 1.609_344)
        #expect(scale(fitted.drawn(in: .metersPerSecond)) == [0, 80, 10, 5])
        // Nothing of the project changed: back in its own unit it is exactly the dial it was.
        #expect(fitted.drawn(in: .kph) == kph && fitted.drawn(in: .mph) == fitted)
    }

    @Test("Its zones are speeds, and are drawn with it")
    func zonesAreDrawnWithIt() throws {
        var zoned = fitted
        zoned.zones = [GaugeZone(from: 100, to: nil, color: .red)]
        let from = try #require(zoned.drawn(in: .kph).zones.first?.from)
        #expect(abs(from - 160.9344) < 0.001)
    }

    @Test("A scale with no unit stands as written, whatever unit is drawn")
    func scalesWithNoUnitStand() {
        var written = fitted
        written.scaleUnit = nil
        #expect(written.drawn(in: .kph) == written)
        // So does a speedometer waiting for its file, and a gauge of anything but a speed.
        #expect(GaugeParams.speedometer().drawn(in: .kph) == GaugeParams.speedometer())
        var revs = GaugeParams.tachometer()
        revs.scaleUnit = .mph
        #expect(revs.drawn(in: .kph) == revs)
    }

    @Test("A bar is drawn the same way")
    func bars() {
        var bar = BarParams(channel: "speed", label: "", minValue: 0, maxValue: 140)
        #expect(bar.drawn(in: .kph) == bar, "no unit: as written")
        bar.scaleUnit = .mph
        let kph = bar.drawn(in: .kph)
        #expect(kph.minValue == 0 && kph.maxValue == 240 && kph.scaleUnit == .kph)
        #expect(bar.drawn(in: .mph) == bar)
    }

    @Test("An edit that changes the unit converts from the unit the numbers are in")
    func reshownFromTheUnitWritten() {
        // Written in mph and drawn in km/h — the unit was changed in Settings — then set to mph
        // on the object: the numbers are already in mph, and nothing is converted.
        var chosen = fitted
        (chosen.maxValue, chosen.majorTick, chosen.minorTick) = (200, 25, 5)
        #expect(chosen.reshown(from: .kph, in: .mph, channels: []) == chosen)
        // A scale with no unit is taken to be in the unit it was drawn in, as before, and from
        // then on says its unit.
        var written = chosen
        written.scaleUnit = nil
        let kph = written.reshown(from: .mph, in: .kph, channels: [])
        #expect(scale(kph) == [0, 350, 50, 25] && kph.scaleUnit == .kph)
    }

    @Test("Numbers typed in the inspector are in the unit the dial is drawn in")
    func typedScales() {
        var written = fitted
        written.scaleUnit = nil
        var typed = written
        typed.maxValue = 180
        #expect(typed.scaleUnitKept(after: written, drawnIn: .kph).scaleUnit == .kph)
        // An edit of anything else leaves the scale's unit as it is: none here.
        var recoloured = written
        recoloured.needleColor = .red
        #expect(recoloured.scaleUnitKept(after: written, drawnIn: .kph).scaleUnit == nil)
        // Pointed at something that is not a speed, the scale is in no unit.
        var revs = fitted
        revs.channel = "rpm"
        #expect(revs.scaleUnitKept(after: fitted, drawnIn: .kph).scaleUnit == nil)
        // And pointed at a speed, it is in the unit drawn.
        var speed = GaugeParams.tachometer()
        speed.channel = "speed"
        #expect(speed.scaleUnitKept(after: .tachometer(), drawnIn: .mph).scaleUnit == .mph)
    }

    @Test("The unit is kept in the project, and left out where there is none")
    func coding() throws {
        let data = try JSONEncoder().encode(fitted)
        #expect(try JSONDecoder().decode(GaugeParams.self, from: data) == fitted)
        var written = fitted
        written.scaleUnit = nil
        let json = try #require(String(data: try JSONEncoder().encode(written), encoding: .utf8))
        #expect(!json.contains("scaleUnit"))
        #expect(try JSONDecoder().decode(GaugeParams.self, from: Data(json.utf8)).scaleUnit == nil)
    }

    @Test("A project saved before schema 9 draws its scales as written, as it always did")
    func migration() throws {
        let input = Input(label: "data", source: MediaReference(path: "x.csv"), kind: .data(DataInputSettings()))
        // A dial as an earlier build saved it, and one given a unit by hand in the file.
        var earlier = fitted
        earlier.scaleUnit = nil
        let dial = DisplayObject(label: "Speed", inputID: input.id, frame: .full, kind: .speedometer(earlier))
        let odd = DisplayObject(label: "Odd", inputID: input.id, frame: .full, kind: .speedometer(fitted))
        var bar = BarParams(channel: "speed", label: "", minValue: 0, maxValue: 140)
        bar.scaleUnit = .mph
        let strip = DisplayObject(label: "Bar", inputID: input.id, frame: .full, kind: .bar(bar))
        var saved = Project(inputs: [input], displayObjects: [dial, odd, strip])
        saved.schemaVersion = 8

        let opened = try Project.decode(try saved.encoded())
        #expect(opened.schemaVersion == 9 && Project.currentSchemaVersion == 9)
        for object in opened.displayObjects {
            if let params = object.kind.gaugeParams {
                #expect(params.scaleUnit == nil, "\(object.label)")
                #expect(scale(params.drawn(in: .kph)) == [0, 160, 20, 10], "\(object.label): drawn as it was")
            } else if case .bar(let params) = object.kind {
                #expect(params.scaleUnit == nil && params.drawn(in: .kph).maxValue == 140)
            }
        }
        // A project of this build keeps the unit when it is opened again.
        let made = Project(inputs: [input], displayObjects: [odd])
        #expect(try Project.decode(try made.encoded()).displayObjects.first?.kind.gaugeParams?.scaleUnit == .mph)
    }
}
