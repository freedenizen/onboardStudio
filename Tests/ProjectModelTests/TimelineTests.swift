import Foundation
import Testing

@testable import ProjectModel

@Suite("Timeline")
struct TimelineTests {
    let camA = DisplayObject(label: "A", inputID: nil, frame: .full, kind: .video(VideoObjectParams()))
    let camB = DisplayObject(
        label: "B", inputID: nil, frame: UnitRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5), isVisible: false,
        kind: .video(VideoObjectParams()))
    let gauge = DisplayObject(
        label: "G", inputID: nil, frame: UnitRect(x: 0.7, y: 0.6, width: 0.2, height: 0.3), opacity: 1,
        kind: .speedometer(.speedometer()))

    var objects: [DisplayObject] { [camA, camB, gauge] }

    func timeline() -> Timeline {
        var timeline = Timeline()
        let s1 = timeline.addSegment(at: 5, label: "cam B")
        timeline.setOverride(ObjectOverride(isVisible: false), for: camA.id, in: s1)
        timeline.setOverride(ObjectOverride(isVisible: true, frame: .full), for: camB.id, in: s1)
        let s2 = timeline.addSegment(at: 10, label: "fade gauge")
        timeline.setOverride(ObjectOverride(opacity: 0.4), for: gauge.id, in: s2)
        return timeline
    }

    @Test func resolvesByInheritance() {
        let timeline = timeline()
        let before = timeline.resolve(objects, at: 2)
        #expect(before == objects)
        let during = timeline.resolve(objects, at: 7)
        #expect(during[0].isVisible == false)
        #expect(during[1].isVisible == true && during[1].frame == .full)
        #expect(during[2].opacity == 1)
        // The second segment inherits the camera switch and adds the opacity change.
        let later = timeline.resolve(objects, at: 12)
        #expect(later[0].isVisible == false && later[1].isVisible == true)
        #expect(later[2].opacity == 0.4)
        #expect(later[2].frame == gauge.frame)
        #expect(timeline.segment(at: 4.999) == nil)
        #expect(timeline.segment(at: 5)?.label == "cam B")
        #expect(timeline.cutPoints(duration: 20) == [0, 5, 10])
        #expect(timeline.cutPoints(duration: 8) == [0, 5])
    }

    @Test func badgesReportWhatASegmentSets() {
        let timeline = timeline()
        let s1 = timeline.segments[0].id
        let s2 = timeline.segments[1].id
        #expect(timeline.overrides(.isVisible, of: camA.id, in: s1))
        #expect(!timeline.overrides(.frame, of: camA.id, in: s1))
        #expect(!timeline.overrides(.isVisible, of: camA.id, in: s2))
        #expect(timeline.overrides(.opacity, of: gauge.id, in: s2))
    }

    @Test func shiftingMovesLaterSegmentsToo() {
        var timeline = timeline()
        let s1 = timeline.segments[0].id
        timeline.shiftSegment(s1, to: 7)
        #expect(timeline.segments.map(\.start) == [7, 12])
        // Cannot move before the previous segment or below zero.
        let s2 = timeline.segments[1].id
        timeline.shiftSegment(s2, to: 1)
        #expect(abs(timeline.segments[1].start - 7.001) < 1e-9)
        timeline.shiftSegment(s1, to: -3)
        #expect(timeline.segments[0].start == 0)
    }

    @Test func deleteAndClearOverrides() {
        var timeline = timeline()
        let s1 = timeline.segments[0].id
        timeline.update(.isVisible, for: camA.id, in: s1) { $0.isVisible = nil }
        #expect(timeline.segment(s1)?.overrides[camA.id] == nil)
        #expect(timeline.resolve(objects, at: 7)[0].isVisible)
        timeline.removeSegment(s1)
        #expect(timeline.segments.count == 1)
        // Later segments still apply once the earlier one is gone.
        #expect(timeline.resolve(objects, at: 12)[2].opacity == 0.4)
        #expect(timeline.resolve(objects, at: 12)[1].isVisible == false)
        timeline.prune(keeping: [camA.id])
        #expect(timeline.segments[0].overrides.isEmpty)
        // Adding at an existing time returns that segment.
        let again = timeline.addSegment(at: 10)
        #expect(again == timeline.segments[0].id)
    }

    @Test func roundTripsAndDecodesLegacyProjects() throws {
        var project = Project(displayObjects: objects, timeline: timeline())
        project.settings.duration = 20
        let data = try project.encoded()
        let decoded = try Project.decode(data)
        #expect(decoded == project)
        let json = String(data: data, encoding: .utf8) ?? ""
        #expect(json.contains("\"timeline\"") && json.contains("\"overrides\""))
        // Override keys are the object UUIDs as strings.
        #expect(json.contains("\"\(camA.id.rawValue.uuidString)\""))
        let legacy = Data(#"{"schemaVersion":1,"inputs":[],"displayObjects":[]}"#.utf8)
        #expect(try Project.decode(legacy).timeline.isEmpty)
    }

    @Test func layoutPresets() {
        let ids = [camA.id, camB.id]
        let pip = LayoutPreset.pictureInPicture.overrides(for: ids)
        #expect(pip[camA.id]?.frame == .full && pip[camA.id]?.isVisible == true)
        #expect(pip[camB.id]?.frame?.width == 0.28)
        let full = LayoutPreset.fullscreen.overrides(for: ids)
        #expect(full[camB.id]?.isVisible == false && full[camB.id]?.frame == nil)
        let quad = LayoutPreset.quad.frames(count: 5)
        #expect(quad.count == 5 && quad[4] == nil && quad[3]?.x == 0.5 && quad[3]?.y == 0.5)
        #expect(LayoutPreset.splitHorizontal.frames(count: 1) == [UnitRect(x: 0, y: 0, width: 0.5, height: 1)])
        #expect(LayoutPreset.fullscreen.frames(count: 0).isEmpty)
    }
}
