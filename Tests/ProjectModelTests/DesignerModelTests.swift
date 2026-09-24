import Foundation
import Testing

@testable import ProjectModel

@Suite("M7 model")
struct DesignerModelTests {
    @Test func legacyGaugeRedlineBecomesAZone() throws {
        let legacy = Data(
            """
            {"channel":"rpm","title":"RPM","minValue":0,"maxValue":8000,"speedUnit":"mph","unitLabel":"rpm",
             "majorTick":1000,"minorTick":500,"sweep":270,"rotation":0,"redlineFrom":6500,"valueDivisor":1,
             "showValue":true,"decimals":0,"faceColor":"#141419BF","needleColor":"#FF9E1A","textColor":"#FFFFFF",
             "redlineColor":"#E62626"}
            """.utf8)
        let params = try JSONDecoder().decode(GaugeParams.self, from: legacy)
        #expect(params.zones.count == 1)
        #expect(params.zones[0].from == 6500 && params.zones[0].to == nil)
        #expect(params.zones[0].color == RGBAColor(hex: "#E62626"))
        #expect(params.redlineFrom == 6500)
        #expect(params.style == .needle && params.needle == NeedleStyle() && params.ticks == TickStyle())
        // Legacy documents with no red line decode with no zones.
        let plain = try JSONDecoder().decode(GaugeParams.self, from: Data(#"{"channel":"speed"}"#.utf8))
        #expect(plain.zones.isEmpty && plain.maxValue == 100 && plain.majorTick == 20)
    }

    @Test func gaugeDesignRoundTrips() throws {
        var params = GaugeParams.tachometer()
        params.style = .dualNeedle
        params.secondChannel = "speed"
        params.counterClockwise = true
        params.needle = NeedleStyle(
            length: 0.5, tailLength: 0.1, width: 0.1, hubRadius: 0.2, tapered: false, smoothingSeconds: 0.5)
        params.ticks = TickStyle(showMinor: false, labelDecimals: 1, declutter: false)
        params.zones = [GaugeZone(from: 3000, to: 5000, color: .accent), GaugeZone(from: 6500, to: nil, color: .red)]
        params.zoneTargets = ZoneTargets(face: false, marks: true, needle: true, gradient: true)
        params.faceImageInputID = InputID()
        params.showFace = false
        let data = try JSONEncoder().encode(params)
        let decoded = try JSONDecoder().decode(GaugeParams.self, from: data)
        #expect(decoded == params)
        #expect(!(String(data: data, encoding: .utf8) ?? "").contains("redlineFrom"))
    }

    @Test func newKindsRoundTrip() throws {
        let kinds: [DisplayObjectKind] = [
            .bar(BarParams(channel: "throttle", zones: [GaugeZone(from: 80)], segments: 10)),
            .graph(
                GraphParams(
                    series: [GraphSeries(channel: "speed"), GraphSeries(channel: "rpm")], axis: .lap, minValue: 0)),
            .gear(GearParams(neutralText: "0")),
            .lapCounter(LapCounterParams(showTotal: true, numberOffset: 1)),
            .timer(TimerParams(mode: .deltaToBest, decimals: 3)),
            .textData(TextDataParams(channel: "rpm", label: "RPM", multiplier: 0.001, thousandsSeparator: true)),
        ]
        for kind in kinds {
            let data = try JSONEncoder().encode(kind)
            #expect(try JSONDecoder().decode(DisplayObjectKind.self, from: data) == kind)
            #expect(kind.needsData && kind.isOverlay)
        }
        // Older timer / text data documents decode with the new defaults.
        let timer = try JSONDecoder().decode(
            TimerParams.self, from: Data(#"{"mode":"bestLap","showLapNumber":false,"label":null}"#.utf8))
        #expect(timer.mode == .bestLap && timer.decimals == 2 && !timer.showLapNumber)
        let text = try JSONDecoder().decode(
            TextDataParams.self, from: Data(#"{"channel":"speed","label":"SPD","decimals":1}"#.utf8))
        #expect(text.multiplier == 1 && text.fontScale == 0.5 && text.decimals == 1)
        #expect(DisplayObject.templates.map(\.name).contains("Graph"))
        #expect(DisplayObject.makeDefault(kind: .gear(GearParams()), inputID: nil, index: 0).frame.width < 0.2)
    }

    @Test func zoneLookup() {
        let zones = [GaugeZone(from: 10, to: 20, color: .accent), GaugeZone(from: 50, to: nil, color: .red)]
        #expect(zones.zone(containing: 5) == nil)
        #expect(zones.zone(containing: 10)?.color == .accent)
        #expect(zones.zone(containing: 20) == nil)
        #expect(zones.zone(containing: 500)?.color == .red)
    }

    @Test func styleRoundTripAndApply() throws {
        var source = DisplayObject(
            label: "Tach", inputID: InputID(), frame: UnitRect(x: 0.5, y: 0.5, width: 0.4, height: 0.4), opacity: 0.8,
            kind: .tachometer(.tachometer(max: 9000)))
        source.kind = .tachometer(
            {
                var p = GaugeParams.tachometer(max: 9000)
                p.style = .arc
                return p
            }())
        let style = ObjectStyle(object: source)
        let data = try style.data()
        let decoded = try ObjectStyle(data: data)
        #expect(decoded == style)
        #expect(
            (String(data: data, encoding: .utf8) ?? "").contains("\"formatVersion\" : \(ObjectStyle.formatVersion)"))

        var target = DisplayObject(
            label: "Other", inputID: nil, frame: UnitRect(x: 0.8, y: 0.9, width: 0.1, height: 0.1),
            kind: .textData(TextDataParams(channel: "rpm", label: "RPM")))
        let id = target.id
        decoded.apply(to: &target)
        #expect(target.id == id && target.label == "Other")
        #expect(target.kind == source.kind && target.opacity == 0.8)
        #expect(target.frame.width == 0.4 && target.frame.height == 0.4)
        // Nudged back inside the frame.
        #expect(target.frame.x == 0.6 && target.frame.y == 0.6)

        #expect(throws: ObjectStyleError.self) {
            try ObjectStyle(
                data: Data(#"{"formatVersion":99,"kind":{"gear":{"_0":{}}},"opacity":1,"width":0.1,"height":0.1}"#.utf8)
            )
        }
    }
}
