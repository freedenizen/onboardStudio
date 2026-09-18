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

@Suite("Clip sequences", .serialized)
struct ClipSequenceTests {
    static var rotated: URL {
        get throws {
            try #require(Bundle.module.url(forResource: "Fixtures", withExtension: nil)).appending(
                path: "test-rot180.mp4")
        }
    }

    @Test func clipsPlayBackToBackAsOneTrack() async throws {
        let clip = try MediaFixtures.video
        // The same 3 s clip twice: the second half of the sequence replays the first.
        let compiled = try await CompositionBuilder.build(
            videos: [VideoInputSpec(url: clip, clips: [clip])], overlays: [], outputWidth: 320, outputHeight: 180,
            frameRate: 30)
        #expect(abs(compiled.duration - 6) < 0.05, "duration \(compiled.duration)")
        #expect(compiled.composition.tracks(withMediaType: .video).count == 1)
        #expect(compiled.composition.tracks(withMediaType: .audio).count == 1)
        let alone = try await CompositionBuilder.build(
            videos: [VideoInputSpec(url: clip)], overlays: [], outputWidth: 320, outputHeight: 180, frameRate: 30)
        let replay = try await MediaFixtures.renderFrame(of: compiled, at: 3.4)
        let original = try await MediaFixtures.renderFrame(of: alone, at: 0.4)
        let later = try await MediaFixtures.renderFrame(of: alone, at: 2.4)
        func distance(_ a: CVPixelBuffer, _ b: CVPixelBuffer) -> Int {
            var total = 0
            for y in stride(from: 5, to: 180, by: 12) {
                for x in stride(from: 5, to: 320, by: 12) {
                    let p = PixelBuffers.pixel(in: a, x: x, y: y)
                    let q = PixelBuffers.pixel(in: b, x: x, y: y)
                    total += abs(Int(p.r) - Int(q.r)) + abs(Int(p.g) - Int(q.g)) + abs(Int(p.b) - Int(q.b))
                }
            }
            return total
        }
        let same = distance(replay, original)
        let different = distance(replay, later)
        #expect(
            same * 4 < different, "3.4 s of the sequence should look like 0.4 s of the clip (\(same) vs \(different))")
    }

    @Test func trimAndSpeedApplyToTheWholeSequence() async throws {
        let first = try MediaFixtures.video
        let second = try MediaFixtures.video
        // Start 2 s into the sequence and stop 1.5 s later, played at double speed → 0.75 s.
        let spec = VideoInputSpec(
            url: first, clips: [second], sync: SyncSettings(offsetInProject: 1, playSpeed: 2),
            trim: TrimRange(start: 2, end: 3.5))
        let compiled = try await CompositionBuilder.build(
            videos: [spec], overlays: [], outputWidth: 160, outputHeight: 90, frameRate: 30)
        #expect(abs(compiled.duration - 1.75) < 0.05, "duration \(compiled.duration)")
        let segments = (compiled.composition.tracks(withMediaType: .video).first?.segments ?? []).filter { !$0.isEmpty }
        #expect(segments.count == 2, "one segment per clip inside the window, got \(segments.count)")
    }
}

extension MediaFixtures {
    /// Renders one frame of a compiled composition through the overlay compositor.
    static func renderFrame(of compiled: CompiledComposition, at time: Double) async throws -> CVPixelBuffer {
        let generator = AVAssetImageGenerator(asset: compiled.composition)
        generator.videoComposition = compiled.videoComposition
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let image = try await generator.image(at: CMTime(seconds: time, preferredTimescale: 600)).image
        let buffer = try PixelBuffers.makeBuffer(width: image.width, height: image.height)
        try PixelBuffers.draw(into: buffer) { context, size in
            context.translateBy(x: 0, y: size.height)
            context.scaleBy(x: 1, y: -1)
            context.draw(image, in: CGRect(origin: .zero, size: size))
        }
        return buffer
    }
}
