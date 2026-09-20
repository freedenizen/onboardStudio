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
        let location = ProjectLocation(URL(fileURLWithPath: "/tmp/x.onboardproj"))
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
        let location = ProjectLocation(URL(fileURLWithPath: "/tmp/x.onboardproj"))
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
        let location = ProjectLocation(URL(fileURLWithPath: "/tmp/x.onboardproj"))
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
        let location = ProjectLocation(URL(fileURLWithPath: "/tmp/x.onboardproj"))
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
            videos: [VideoInputSpec(url: clip, clips: [ClipSpec(url: clip)])], overlays: [], outputWidth: 320,
            outputHeight: 180,
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
            url: first, clips: [ClipSpec(url: second)], sync: SyncSettings(offsetInProject: 1, playSpeed: 2),
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

@Suite("Clip trims, gaps and orientation", .serialized)
struct ClipEditingTests {
    @Test func perClipTrimAndGapShapeTheSequence() async throws {
        let clip = try MediaFixtures.video
        // 3 s + (1 s gap + 1.5 s of the second file, seconds 1…2.5) = 5.5 s.
        let spec = VideoInputSpec(
            url: clip, clips: [ClipSpec(url: clip, trim: TrimRange(start: 1, end: 2.5), gapBefore: 1)])
        let compiled = try await CompositionBuilder.build(
            videos: [spec], overlays: [], outputWidth: 160, outputHeight: 90, frameRate: 30)
        #expect(abs(compiled.duration - 5.5) < 0.05, "duration \(compiled.duration)")
        let segments = compiled.composition.tracks(withMediaType: .video).first?.segments ?? []
        let filled = segments.filter { !$0.isEmpty }
        #expect(filled.count == 2)
        // The second file's played part starts at project 4 s and plays its second 1…2.5.
        let second = try #require(filled.last)
        #expect(abs(second.timeMapping.target.start.seconds - 4) < 0.02)
        #expect(abs(second.timeMapping.source.start.seconds - 1) < 0.02)
        #expect(abs(second.timeMapping.source.duration.seconds - 1.5) < 0.02)
        // The gap renders black.
        let gap = try await MediaFixtures.renderFrame(of: compiled, at: 3.5)
        let p = PixelBuffers.pixel(in: gap, x: 80, y: 45)
        #expect(p.r < 10 && p.g < 10 && p.b < 10, "gap pixel \(p)")
    }

    @Test func clipsWithDifferentOrientationsEachKeepTheirs() async throws {
        let upright = try MediaFixtures.video
        let rotated = try ClipSequenceTests.rotated
        let compiled = try await CompositionBuilder.build(
            videos: [VideoInputSpec(url: upright, clips: [ClipSpec(url: rotated)])], overlays: [], outputWidth: 320,
            outputHeight: 180, frameRate: 30)
        let track = compiled.trackIDs[0]
        #expect(compiled.orientationSpans[track]?.count == 2)
        #expect(compiled.orientationChangeTimes.count == 1)
        #expect(abs((compiled.orientationChangeTimes.first ?? 0) - 3) < 0.05)
        #expect(compiled.sourceTransforms(at: 1)[track] == .identity)
        #expect(compiled.sourceTransforms(at: 3.5)[track] != .identity)
        // Through the project compiler the second clip is drawn upright like the rotated clip alone.
        let loaded = ProjectCompiler.LoadedProject(
            project: Project(
                inputs: [], displayObjects: [], export: ExportSettings()),
            location: ProjectLocation(URL(fileURLWithPath: "/tmp/x.onboardproj")),
            sessions: [:], mediaInfo: [:])
        _ = loaded
        let plans = ProjectCompiler.timedPlans(
            for: try await ClipEditingTests.project(upright: upright, rotated: rotated), trackIDs: [:],
            sourceTransforms: { compiled.sourceTransforms(at: $0) },
            orientationChanges: compiled.orientationChangeTimes,
            duration: compiled.duration)
        #expect(plans.count == 2 && abs(plans[1].start - 3) < 0.05)
    }

    static func project(upright: URL, rotated: URL) async throws -> ProjectCompiler.LoadedProject {
        var settings = VideoInputSettings()
        settings.clips = [VideoClip(source: MediaReference(path: rotated.path))]
        let video = Input(label: "v", source: MediaReference(path: upright.path), kind: .video(settings))
        let project = Project(
            inputs: [video],
            displayObjects: [
                DisplayObject(label: "v", inputID: video.id, frame: .full, kind: .video(VideoObjectParams()))
            ])
        return try await ProjectCompiler.load(
            project, location: ProjectLocation(URL(fileURLWithPath: "/tmp/y.onboardproj")))
    }

    @Test func rotatedSecondClipRendersUprightEndToEnd() async throws {
        let upright = try MediaFixtures.video
        let rotated = try ClipSequenceTests.rotated
        let loaded = try await Self.project(upright: upright, rotated: rotated)
        let compiled = try await ProjectCompiler.compile(loaded)
        let alone = try await CompositionBuilder.build(
            videos: [VideoInputSpec(url: rotated)], overlays: [], outputWidth: 1920, outputHeight: 1080, frameRate: 30)
        let sequenceFrame = try await MediaFixtures.renderFrame(of: compiled, at: 3.4)
        let aloneFrame = try await MediaFixtures.renderFrame(of: alone, at: 0.4)
        var agree = 0
        for (x, y) in [(200, 200), (960, 540), (1700, 900), (600, 300), (1300, 700)] {
            let a = PixelBuffers.pixel(in: sequenceFrame, x: x, y: y)
            let b = PixelBuffers.pixel(in: aloneFrame, x: x, y: y)
            if abs(Int(a.r) - Int(b.r)) < 40, abs(Int(a.g) - Int(b.g)) < 40, abs(Int(a.b) - Int(b.b)) < 40 {
                agree += 1
            }
        }
        #expect(agree >= 4, "\(agree) of 5 probes match the rotated clip played alone")
    }
}

@Suite("Clip speed", .serialized)
struct ClipSpeedTests {
    @Test func aFastClipTakesLessOfTheSequence() async throws {
        let clip = try MediaFixtures.video
        // 3 s at normal speed, then the same 3 s file at double speed → 1.5 s more = 4.5 s.
        let spec = VideoInputSpec(url: clip, clips: [ClipSpec(url: clip, speed: 2)])
        let compiled = try await CompositionBuilder.build(
            videos: [spec], overlays: [], outputWidth: 160, outputHeight: 90, frameRate: 30)
        #expect(abs(compiled.duration - 4.5) < 0.05, "duration \(compiled.duration)")
        let segments = (compiled.composition.tracks(withMediaType: .video).first?.segments ?? []).filter { !$0.isEmpty }
        #expect(segments.count == 2)
        let fast = try #require(segments.last)
        #expect(abs(fast.timeMapping.source.duration.seconds - 3) < 0.02)
        #expect(abs(fast.timeMapping.target.duration.seconds - 1.5) < 0.02)
        // The picture 1 s into the fast clip (project 4 s) is the file's 2 s frame.
        let sequenceFrame = try await MediaFixtures.renderFrame(of: compiled, at: 4.0)
        let alone = try await CompositionBuilder.build(
            videos: [VideoInputSpec(url: clip)], overlays: [], outputWidth: 160, outputHeight: 90, frameRate: 30)
        let expected = try await MediaFixtures.renderFrame(of: alone, at: 2.0)
        let wrong = try await MediaFixtures.renderFrame(of: alone, at: 1.0)
        func distance(_ a: CVPixelBuffer, _ b: CVPixelBuffer) -> Int {
            var total = 0
            for y in stride(from: 3, to: 90, by: 6) {
                for x in stride(from: 3, to: 160, by: 6) {
                    let p = PixelBuffers.pixel(in: a, x: x, y: y)
                    let q = PixelBuffers.pixel(in: b, x: x, y: y)
                    total += abs(Int(p.r) - Int(q.r)) + abs(Int(p.g) - Int(q.g)) + abs(Int(p.b) - Int(q.b))
                }
            }
            return total
        }
        #expect(distance(sequenceFrame, expected) * 2 < distance(sequenceFrame, wrong))
    }

    @Test func speedDecodesAndCountsInTheLoadedDuration() throws {
        let clip = try JSONDecoder().decode(
            VideoClip.self, from: Data(#"{"source": {"path": "a.mp4"}, "speed": 4}"#.utf8))
        #expect(clip.speed == 4 && clip.sequenceDuration(played: 8) == 2)
        let legacy = try JSONDecoder().decode(VideoClip.self, from: Data(#"{"path": "a.mp4"}"#.utf8))
        #expect(legacy.speed == 1)
    }
}
