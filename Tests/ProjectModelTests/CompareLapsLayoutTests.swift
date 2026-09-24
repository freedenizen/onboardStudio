import Foundation
import Testing

@testable import ProjectModel

@Suite("Compare Laps layout (#154)")
struct CompareLapsLayoutTests {
    let video = Input(label: "Cam", source: MediaReference(path: "/tmp/c.mp4"), kind: .video(VideoInputSettings()))
    let otherVideo = Input(
        label: "Cam 2", source: MediaReference(path: "/tmp/d.mp4"), kind: .video(VideoInputSettings()))
    let data = Input(label: "Log", source: MediaReference(path: "/tmp/l.csv"), kind: .data(DataInputSettings()))
    let otherData = Input(label: "Log 2", source: MediaReference(path: "/tmp/m.csv"), kind: .data(DataInputSettings()))

    func settings(_ layout: LapComparisonLayout = .sideBySide) -> LapComparisonSettings {
        LapComparisonSettings(
            lap: .init(dataInputID: data.id, videoInputID: video.id, lap: 7),
            comparedLap: .init(dataInputID: otherData.id, videoInputID: otherVideo.id, lap: 3), layout: layout)
    }

    @Test func eachLapGetsItsPictureAndReadoutsAndTheDeltaSitsBetween() throws {
        var project = Project(
            inputs: [video, otherVideo, data, otherData],
            displayObjects: [DisplayObject(label: "Old", inputID: nil, frame: .full, kind: .text(TextParams()))])
        project.compareLaps(settings(), lapRange: 100...192.5)
        #expect(project.lapComparison == settings())
        #expect(project.export.range == .span(start: 100, end: 192.5))
        #expect(!project.displayObjects.contains { $0.label == "Old" })
        // The lap's objects read its own inputs; the compared lap's read the others and follow it.
        let lap = project.displayObjects.filter { !$0.followsComparedLap && $0.label != "Delta" }
        let compared = project.displayObjects.filter(\.followsComparedLap)
        #expect(lap.count == 3 && compared.count == 3)
        #expect(Set(lap.compactMap(\.inputID)) == [video.id, data.id])
        #expect(Set(compared.compactMap(\.inputID)) == [otherVideo.id, otherData.id])
        // Side by side: two 16:9 halves.
        let pictures = project.videoObjects.map(\.frame)
        #expect(pictures.map(\.x) == [0, 0.5] && pictures.allSatisfy { $0.width == 0.5 && $0.height == 0.5 })
        let delta = try #require(project.displayObjects.first { $0.label == "Delta" })
        guard case .timer(let timer) = delta.kind else {
            Issue.record("the delta is not a timer")
            return
        }
        #expect(timer.mode == .deltaToBest && timer.deltaReference == .comparedLap)
    }

    @Test func stackedPutsOnePictureAboveTheOther() {
        var project = Project(inputs: [video, otherVideo, data, otherData])
        project.compareLaps(settings(.stacked), lapRange: nil)
        #expect(project.videoObjects.map(\.frame.y) == [0, 0.5])
        #expect(project.export.range == ExportSettings.hd1080.range)
    }

    @Test func stoppingKeepsTheLapAndDropsTheComparedLap() {
        var project = Project(inputs: [video, otherVideo, data, otherData])
        project.compareLaps(settings(), lapRange: nil)
        project.stopComparingLaps()
        #expect(project.lapComparison == nil)
        #expect(!project.displayObjects.contains { $0.followsComparedLap })
        #expect(project.videoObjects.count == 1)
    }

    @Test func aProjectSavedBeforeComparingOpensAsNotComparing() throws {
        var project = Project(inputs: [video, data])
        project.displayObjects = [
            DisplayObject(label: "v", inputID: video.id, frame: .full, kind: .video(VideoObjectParams()))
        ]
        var json = try #require(try JSONSerialization.jsonObject(with: try project.encoded()) as? [String: Any])
        json["lapComparison"] = nil
        var objects = try #require(json["displayObjects"] as? [[String: Any]])
        objects[0]["followsComparedLap"] = nil
        json["displayObjects"] = objects
        let opened = try Project.decode(try JSONSerialization.data(withJSONObject: json))
        #expect(opened.lapComparison == nil)
        #expect(opened.displayObjects.first?.followsComparedLap == false)
        // And a comparing project keeps its comparison through a save.
        project.compareLaps(settings(), lapRange: nil)
        #expect(try Project.decode(try project.encoded()).lapComparison == settings())
    }
}
