import Foundation
import Testing

@testable import ProjectModel

@Suite("Cockpit with Graph template (#296)")
struct CockpitWithGraphTemplateTests {
    let template = ProjectTemplate.cockpitWithGraph

    func frame(_ label: String) throws -> UnitRect {
        try #require(template.displayObjects.first { $0.label == label }, "no \(label)").frame
    }

    /// In 1080p pixels, where the layout was drawn.
    func pixels(_ label: String) throws -> UnitRect {
        let rect = try frame(label)
        return UnitRect(x: rect.x * 1920, y: rect.y * 1080, width: rect.width * 1920, height: rect.height * 1080)
    }

    @Test func isABuiltInTemplate() {
        #expect(ProjectTemplate.builtIn.contains { $0.name == "Cockpit with Graph" })
    }

    @Test func centredAndMirroredAboutTheMiddle() throws {
        let rpm = try pixels("RPM")
        let speed = try pixels("Speed")
        #expect(abs((rpm.x + rpm.width) + speed.x - 1920) < 0.01, "RPM and Speed mirror about the centre")
        #expect(rpm.width == speed.width && rpm.height == speed.height && rpm.y == speed.y)
        #expect(abs(rpm.width - rpm.height) < 0.01, "square dials")
        let wheel = try pixels("Wheel")
        #expect(abs(wheel.x + wheel.width / 2 - 960) < 0.01 && abs(wheel.y + wheel.height / 2 - 1080) < 0.01)
        #expect(abs(wheel.width - wheel.height) < 0.01)
        let panel = try pixels("Timing Panel")
        #expect(abs(panel.x + panel.width / 2 - 960) < 0.01)
        let gear = try pixels("Gear")
        #expect(abs(gear.x + gear.width / 2 - (rpm.x + rpm.width / 2)) < 0.01)
        #expect(abs(gear.y + gear.height / 2 - (rpm.y + rpm.height / 2)) < 0.01)
    }

    @Test func everythingKeepsTheSameMargin() throws {
        let margin = 24.0
        for label in ["G", "Brake", "Throttle", "RPM", "Speed", "Graph"] {
            let rect = try pixels(label)
            #expect(abs(rect.y + rect.height - (1080 - margin)) < 0.01, "\(label) sits on the bottom margin")
        }
        #expect(abs(try pixels("G").x - margin) < 0.01)
        let map = try pixels("Map")
        #expect(abs(map.x - margin) < 0.01 && abs(map.y - margin) < 0.01)
        #expect(abs(try pixels("Timing Panel").y - margin) < 0.01)
        let graph = try pixels("Graph")
        #expect(abs(graph.x + graph.width - (1920 - margin)) < 0.01)
        // The graph balances the G meter and bars on the other side.
        let throttle = try pixels("Throttle")
        #expect(abs(graph.width - (throttle.x + throttle.width - margin)) < 0.01)
    }

    @Test func lightsSitCentredOverTheirBars() throws {
        for (light, bar) in [("ABS", "Brake"), ("DSC", "Throttle")] {
            let l = try pixels(light)
            let b = try pixels(bar)
            #expect(abs(l.x + l.width / 2 - (b.x + b.width / 2)) < 0.01, "\(light) over \(bar)")
            #expect(l.y + l.height < b.y, "\(light) above \(bar)")
        }
        #expect(try frame("ABS").width == frame("DSC").width && frame("ABS").height == frame("DSC").height)
        #expect(try frame("Brake").width == frame("Throttle").width)
    }

    @Test func graphShowsWhatIsComingAndTheTachWarnsBeforeTheRedline() throws {
        let objects = template.displayObjects
        guard case .graph(let graph)? = objects.first(where: { $0.label == "Graph" })?.kind else {
            Issue.record("no graph")
            return
        }
        #expect(graph.playheadPosition == GraphParams.middlePlayheadPosition && graph.showPlayheadLine)
        #expect(graph.series.map(\.channel) == ["brake", "throttle"])
        guard case .tachometer(let rpm)? = objects.first(where: { $0.label == "RPM" })?.kind else {
            Issue.record("no tachometer")
            return
        }
        #expect(rpm.zones.map(\.from) == [6500, 7200] && rpm.zones.map(\.to) == [7200, nil])
        guard case .trackMap(let map)? = objects.first(where: { $0.label == "Map" })?.kind else {
            Issue.record("no map")
            return
        }
        #expect(map.dotRadius == 10 && map.dotColor.red == 1 && map.dotColor.green < 0.3)
    }

    /// Nothing names one logger's channels or units: the lights and wheel start unbound and find
    /// theirs in the data, and speeds follow the project.
    @Test func bindsToWhateverTheDataOffers() {
        var project = template.makeProject()
        for object in project.displayObjects {
            switch object.kind {
            case .indicator(let params): #expect(params.channel.isEmpty, "\(object.label)")
            case .steeringWheel(let params): #expect(params.channel.isEmpty)
            case .speedometer(let params): #expect(params.speedUnit == .automatic)
            case .lapPanel(let params): #expect(params.speedUnit == .automatic)
            default: break
            }
        }
        let data = Input(label: "log", source: MediaReference(path: "/log.csv"), kind: .data(DataInputSettings()))
        project.inputs.append(data)
        project.bindOrphanObjects()
        let channels = [
            ChannelSummary(identifier: "speed", name: "speed", minValue: 0, maxValue: 60),
            ChannelSummary(identifier: "aux:ABS_Active", name: "ABS_Active", minValue: 0, maxValue: 1),
            ChannelSummary(identifier: "aux:DSC", name: "DSC", minValue: 0, maxValue: 1),
            ChannelSummary(identifier: "obd:steering_angle", name: "steering_angle", minValue: -173, maxValue: 160),
        ]
        let bound = Set(project.bindEmptyChannels([data.id: channels]))
        #expect(bound.isSuperset(of: ["ABS", "DSC", "Wheel"]))
        func channel(_ label: String) -> String? {
            switch project.displayObjects.first(where: { $0.label == label })?.kind {
            case .indicator(let params): params.channel
            case .steeringWheel(let params): params.channel
            default: nil
            }
        }
        #expect(channel("ABS") == "aux:ABS_Active")
        #expect(channel("DSC") == "aux:DSC")
        #expect(channel("Wheel") == "obd:steering_angle")
    }
}
