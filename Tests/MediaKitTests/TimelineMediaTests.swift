import AVFoundation
import Foundation
import Testing

@testable import MediaKit
@testable import ProjectModel
@testable import RenderKit

@Suite("Timeline media", .serialized)
struct TimelineMediaTests {
    /// Two cameras: A full screen, then at 1.5 s A hidden and B in the top-left quarter.
    func project() throws -> Project {
        let a = Input(
            label: "A", source: MediaReference(path: try MediaFixtures.video.path), kind: .video(VideoInputSettings()))
        let b = Input(
            label: "B", source: MediaReference(path: try MediaFixtures.video.path), kind: .video(VideoInputSettings()))
        let camA = DisplayObject(label: "A", inputID: a.id, frame: .full, kind: .video(VideoObjectParams()))
        let camB = DisplayObject(
            label: "B", inputID: b.id, frame: UnitRect(x: 0, y: 0, width: 0.5, height: 0.5), isVisible: false,
            kind: .video(VideoObjectParams()))
        var project = Project(inputs: [a, b], displayObjects: [camA, camB])
        project.settings.outputWidth = 320
        project.settings.outputHeight = 180
        let segment = project.timeline.addSegment(at: 1.5, label: "switch")
        project.timeline.setOverride(ObjectOverride(isVisible: false), for: camA.id, in: segment)
        project.timeline.setOverride(ObjectOverride(isVisible: true), for: camB.id, in: segment)
        return project
    }

    @Test func compileMakesOneInstructionPerSegment() async throws {
        let project = try project()
        let location = ProjectLocation(URL(fileURLWithPath: "/tmp/x.overlayproj"))
        let compiled = try await ProjectCompiler.compile(try await ProjectCompiler.load(project, location: location))
        #expect(compiled.plans.map(\.start) == [0, 1.5])
        #expect(compiled.plans[0].plan.videoLayers.count == 1)
        #expect(compiled.plans[1].plan.videoLayers.count == 1)
        #expect(compiled.plans[0].plan.videoLayers[0].trackID != compiled.plans[1].plan.videoLayers[0].trackID)
        let instructions = compiled.videoComposition.instructions
        #expect(instructions.count == 2)
        #expect(instructions[0].timeRange.start == .zero)
        #expect(abs(instructions[0].timeRange.end.seconds - 1.5) < 1e-6)
        #expect(abs(instructions[1].timeRange.start.seconds - 1.5) < 1e-6)
        #expect(abs(instructions[1].timeRange.end.seconds - compiled.duration) < 1e-6)
        // Every instruction requires both tracks so a switch never waits on an undecoded track.
        #expect(instructions.allSatisfy { ($0.requiredSourceTrackIDs?.count ?? 0) == 2 })
    }

    @Test func exportSwitchesCameraAtTheSegmentStart() async throws {
        let output = MediaFixtures.temporaryOutput("switch")
        defer { try? FileManager.default.removeItem(at: output) }
        let project = try project()
        let location = ProjectLocation(URL(fileURLWithPath: "/tmp/x.overlayproj"))
        let compiled = try await ProjectCompiler.compile(try await ProjectCompiler.load(project, location: location))
        var settings = ExportSettings(width: 320, height: 180, frameRate: 30, videoBitrate: 1_000_000)
        settings.audioBitrate = nil
        for try await _ in Exporter.export(compiled, settings: settings, to: output) {}
        // Bottom-right quarter: camera A fills it before the switch; afterwards only B's top-left
        // quarter is drawn, so it is black.
        func brightness(at time: Double) async throws -> Int {
            let frame = try await MediaFixtures.frame(of: output, at: time)
            var total = 0
            for y in stride(from: 120, to: 170, by: 10) {
                for x in stride(from: 200, to: 310, by: 10) {
                    let p = PixelBuffers.pixel(in: frame, x: x, y: y)
                    total += Int(p.r) + Int(p.g) + Int(p.b)
                }
            }
            return total / (5 * 11)
        }
        #expect(try await brightness(at: 1.0) > 60)
        #expect(try await brightness(at: 2.0) < 12)
        // And B's quarter is drawn after the switch.
        let after = try await MediaFixtures.frame(of: output, at: 2.0)
        let p = PixelBuffers.pixel(in: after, x: 80, y: 45)
        #expect(Int(p.r) + Int(p.g) + Int(p.b) > 60)
    }

    @Test func hiddenCameraKeepsItsRotationWhenShownLater() async throws {
        // Both cameras are the 180°-rotated fixture; B is hidden at compile time.
        let rotated = try SourceOrientationMediaTests.rotated
        let a = Input(label: "A", source: MediaReference(path: rotated.path), kind: .video(VideoInputSettings()))
        let b = Input(label: "B", source: MediaReference(path: rotated.path), kind: .video(VideoInputSettings()))
        var project = Project(
            inputs: [a, b],
            displayObjects: [
                DisplayObject(label: "A", inputID: a.id, frame: .full, kind: .video(VideoObjectParams())),
                DisplayObject(
                    label: "B", inputID: b.id, frame: .full, isVisible: false, kind: .video(VideoObjectParams())),
            ])
        project.settings.outputWidth = 320
        project.settings.outputHeight = 180
        let location = ProjectLocation(URL(fileURLWithPath: "/tmp/x.overlayproj"))
        let loaded = try await ProjectCompiler.load(project, location: location)
        let compiled = try await ProjectCompiler.compile(loaded)
        #expect(compiled.plan.videoLayers.count == 1)
        #expect(compiled.sourceTransforms.count == 2)
        project.displayObjects[1].isVisible = true
        let replanned = ProjectCompiler.replan(
            compiled, for: try await ProjectCompiler.load(project, location: location, reusing: loaded))
        #expect(replanned.plan.videoLayers.count == 2)
        #expect(replanned.plan.videoLayers.allSatisfy { $0.sourceTransform != .identity })
    }

    @Test func replanFollowsTimelineEdits() async throws {
        var project = try project()
        let location = ProjectLocation(URL(fileURLWithPath: "/tmp/x.overlayproj"))
        let loaded = try await ProjectCompiler.load(project, location: location)
        let compiled = try await ProjectCompiler.compile(loaded)
        project.timeline.shiftSegment(project.timeline.segments[0].id, to: 2.25)
        #expect(!ProjectCompiler.needsRecompile(from: loaded.project, to: project))
        let replanned = ProjectCompiler.replan(
            compiled, for: try await ProjectCompiler.load(project, location: location, reusing: loaded))
        #expect(replanned.plans.map(\.start) == [0, 2.25])
        #expect(replanned.videoComposition.instructions.count == 2)
        #expect(
            replanned.plans[0].plan.videoLayers[0].sourceTransform
                == compiled.plans[0].plan.videoLayers[0].sourceTransform)
    }
}
