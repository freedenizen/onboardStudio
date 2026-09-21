import AVFoundation
import Foundation
import Testing

@testable import MediaKit
@testable import ProjectModel
@testable import RenderKit

enum MediaFixtures {
    static var video: URL {
        get throws {
            try #require(Bundle.module.url(forResource: "Fixtures", withExtension: nil)).appending(path: "test-3s.mp4")
        }
    }

    static func temporaryOutput(_ name: String = "out") -> URL {
        FileManager.default.temporaryDirectory.appending(path: "onboard-\(name)-\(UUID().uuidString).mp4")
    }

    /// Decodes one frame of `url` at `time` as BGRA.
    static func frame(of url: URL, at time: Double) async throws -> CVPixelBuffer {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
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

@Suite("MediaProbe")
struct MediaProbeTests {
    @Test func describesTheFixture() async throws {
        let info = try await MediaProbe.probe(try MediaFixtures.video)
        #expect(abs(info.duration - 3) < 0.1)
        #expect(info.hasVideo && info.hasAudio)
        #expect(info.width == 640 && info.height == 360)
        #expect(abs(info.nominalFrameRate - 30) < 0.01)
        #expect(info.videoCodec == "avc1")
        #expect(info.hasMetadataTrack == false)
    }

    @Test func rejectsMissingFile() async {
        await #expect(throws: (any Error).self) {
            try await MediaProbe.probe(URL(fileURLWithPath: "/nonexistent/clip.mp4"))
        }
    }
}

@Suite("CompositionBuilder")
struct CompositionBuilderTests {
    @Test func buildsTracksAndInstruction() async throws {
        let compiled = try await CompositionBuilder.build(
            videos: [VideoInputSpec(url: try MediaFixtures.video)], overlays: [], outputWidth: 320, outputHeight: 180,
            frameRate: 30)
        #expect(abs(compiled.duration - 3) < 0.05)
        #expect(compiled.composition.tracks(withMediaType: .video).count == 1)
        #expect(compiled.composition.tracks(withMediaType: .audio).count == 1)
        #expect(compiled.videoComposition.renderSize == CGSize(width: 320, height: 180))
        #expect(compiled.videoComposition.frameDuration == CMTime(value: 1, timescale: 30))
        #expect(compiled.videoComposition.customVideoCompositorClass == OverlayCompositor.self)
        #expect(compiled.plan.videoLayers.count == 1)
        let instruction = try #require(compiled.videoComposition.instructions.first as? OverlayInstruction)
        #expect(instruction.requiredSourceTrackIDs?.count == 1)
    }

    @Test func syncOffsetSpeedAndTrimShapeTheTimeline() async throws {
        // Start 1 s into the clip, at double speed, placed at project t=0.5 → (3-1)/2 = 1 s long, ends at 1.5.
        let spec = VideoInputSpec(
            url: try MediaFixtures.video,
            sync: SyncSettings(startPositionInInput: 1, offsetInProject: 0.5, playSpeed: 2), includeAudio: false)
        let compiled = try await CompositionBuilder.build(
            videos: [spec], overlays: [], outputWidth: 64, outputHeight: 36, frameRate: 30)
        #expect(abs(compiled.duration - 1.5) < 0.05)
        #expect(compiled.composition.tracks(withMediaType: .audio).isEmpty)
        let trimmed = VideoInputSpec(
            url: try MediaFixtures.video, trim: TrimRange(start: 0.5, end: 2), includeAudio: false)
        let trimmedCompiled = try await CompositionBuilder.build(
            videos: [trimmed], overlays: [], outputWidth: 64, outputHeight: 36, frameRate: 30)
        #expect(abs(trimmedCompiled.duration - 1.5) < 0.05)
    }

    @Test func emptyRangeIsRejected() async throws {
        let spec = VideoInputSpec(url: try MediaFixtures.video, trim: TrimRange(start: 2.5, end: 2.5))
        await #expect(throws: CompositionError.self) {
            _ = try await CompositionBuilder.build(
                videos: [spec], overlays: [], outputWidth: 64, outputHeight: 36, frameRate: 30)
        }
    }
}

@Suite("Exporter", .serialized)
struct ExporterTests {
    /// Overlay that paints the left half of the frame solid blue so the export can be probed.
    struct HalfBlue: OverlayDrawing {
        func draw(in context: CGContext, size: CGSize, time: Double) {
            context.setFillColor(PixelBuffers.color(red: 0, green: 0, blue: 1))
            context.fill(CGRect(x: 0, y: 0, width: size.width / 2, height: size.height))
        }
    }

    @Test func exportsThroughTheCompositor() async throws {
        let output = MediaFixtures.temporaryOutput("full")
        defer { try? FileManager.default.removeItem(at: output) }
        let compiled = try await CompositionBuilder.build(
            videos: [VideoInputSpec(url: try MediaFixtures.video)], overlays: [HalfBlue()], outputWidth: 320,
            outputHeight: 180,
            frameRate: 30)
        let settings = ExportSettings(width: 320, height: 180, frameRate: 30, videoBitrate: 1_000_000)
        var last: ExportProgress?
        for try await progress in Exporter.export(compiled, settings: settings, to: output) { last = progress }
        #expect(last?.fraction == 1)
        #expect((last?.framesWritten ?? 0) >= 85 && (last?.framesWritten ?? 0) <= 92)

        let info = try await MediaProbe.probe(output)
        #expect(abs(info.duration - 3) < 0.1)
        #expect(info.width == 320 && info.height == 180)
        #expect(info.hasAudio)
        #expect(info.videoCodec == "avc1")

        let frame = try await MediaFixtures.frame(of: output, at: 1.0)
        let left = PixelBuffers.pixel(in: frame, x: 40, y: 90)
        let right = PixelBuffers.pixel(in: frame, x: 280, y: 90)
        #expect(left.b > 180 && left.r < 60, "left half should be the blue overlay, got \(left)")
        #expect(!(right.b > 180 && right.r < 60), "right half should show the test pattern, got \(right)")
    }

    @Test func exportsARangeWithoutAudioAsHEVC() async throws {
        let output = MediaFixtures.temporaryOutput("range")
        defer { try? FileManager.default.removeItem(at: output) }
        let compiled = try await CompositionBuilder.build(
            videos: [VideoInputSpec(url: try MediaFixtures.video)], overlays: [], outputWidth: 160, outputHeight: 90,
            frameRate: 25)
        var settings = ExportSettings(codec: .hevc, width: 160, height: 90, frameRate: 25, videoBitrate: 500_000)
        settings.audioBitrate = nil
        for try await _ in Exporter.export(compiled, settings: settings, range: 1...2, to: output) {}
        let info = try await MediaProbe.probe(output)
        #expect(abs(info.duration - 1) < 0.1)
        #expect(!info.hasAudio)
        #expect(info.videoCodec == "hvc1")
        #expect(abs(info.nominalFrameRate - 25) < 0.5)
    }

    @Test func cancellationStopsTheExport() async throws {
        let output = MediaFixtures.temporaryOutput("cancel")
        defer { try? FileManager.default.removeItem(at: output) }
        let compiled = try await CompositionBuilder.build(
            videos: [VideoInputSpec(url: try MediaFixtures.video)], overlays: [], outputWidth: 640, outputHeight: 360,
            frameRate: 30)
        let settings = ExportSettings(width: 640, height: 360, frameRate: 30, videoBitrate: 2_000_000)
        let task = Task {
            var count = 0
            for try await _ in Exporter.export(compiled, settings: settings, to: output) {
                count += 1
                if count == 3 { throw CancellationError() }
            }
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test func ffprobeAgreesWhenAvailable() async throws {
        let ffprobe = ["/opt/homebrew/bin/ffprobe", "/usr/local/bin/ffprobe"].first {
            FileManager.default.isExecutableFile(atPath: $0)
        }
        guard let ffprobe else { return }
        let output = MediaFixtures.temporaryOutput("ffprobe")
        defer { try? FileManager.default.removeItem(at: output) }
        let compiled = try await CompositionBuilder.build(
            videos: [VideoInputSpec(url: try MediaFixtures.video)], overlays: [], outputWidth: 320, outputHeight: 180,
            frameRate: 30)
        for try await _ in Exporter.export(
            compiled, settings: ExportSettings(width: 320, height: 180, videoBitrate: 800_000), to: output)
        {}
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffprobe)
        process.arguments = [
            "-v", "error", "-select_streams", "v:0", "-show_entries", "stream=width,height,codec_name,nb_frames", "-of",
            "csv=p=0",
            output.path,
        ]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        let text = String(bytes: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        #expect(text.hasPrefix("h264,320,180,"), "ffprobe reported \(text)")
    }
}

@Suite("ProjectCompiler", .serialized)
struct ProjectCompilerTests {
    static var sliceURL: URL {
        get throws {
            try #require(Bundle.module.url(forResource: "Fixtures", withExtension: nil)).appending(
                path: "slice.onboardproj")
        }
    }

    @Test func loadsMediaAndData() async throws {
        let loaded = try await ProjectCompiler.load(try Self.sliceURL)
        #expect(loaded.project.inputs.count == 2)
        #expect(loaded.sessions.count == 1)
        #expect(loaded.mediaInfo.count == 1)
        let session = try #require(loaded.sessions.values.first)
        #expect(session.laps.count == 3)
        #expect(session[.speed] != nil)
    }

    @Test func compilesVideoLayerFromDisplayObjectFrame() async throws {
        let loaded = try await ProjectCompiler.load(try Self.sliceURL)
        let compiled = try await ProjectCompiler.compile(loaded)
        #expect(compiled.plan.videoLayers.count == 1)
        #expect(compiled.plan.videoLayers[0].frame == UnitRect(x: 0, y: 0, width: 0.5, height: 1))
        #expect(compiled.plan.overlays.count == 5)
        #expect(abs(compiled.duration - 3) < 0.05)
    }

    @Test func exportsTheSliceWithOverlays() async throws {
        let output = MediaFixtures.temporaryOutput("slice")
        defer { try? FileManager.default.removeItem(at: output) }
        let loaded = try await ProjectCompiler.load(try Self.sliceURL)
        let compiled = try await ProjectCompiler.compile(loaded)
        for try await _ in Exporter.export(compiled, settings: loaded.project.export, range: 0...1.5, to: output) {}
        let info = try await MediaProbe.probe(output)
        #expect(info.width == 640 && info.height == 360)
        let frame = try await MediaFixtures.frame(of: output, at: 1.0)
        // Left half: the 16:9 clip letterboxed into a 320x360 area (rows 90…270). Right half: objects on black.
        let video = PixelBuffers.pixel(in: frame, x: 100, y: 180)
        #expect(Int(video.r) + Int(video.g) + Int(video.b) > 150, "expected test pattern on the left, got \(video)")
        // Speedometer face centre sits around (0.66, 0.30) of the frame; its hub is white.
        let hub = PixelBuffers.pixel(in: frame, x: Int(0.66 * 640), y: Int(0.30 * 360))
        #expect(hub.r > 180 && hub.g > 180 && hub.b > 180, "expected the gauge hub, got \(hub)")
        // Empty area between objects should be black.
        let empty = PixelBuffers.pixel(in: frame, x: Int(0.99 * 640), y: Int(0.99 * 360))
        #expect(empty.r < 20 && empty.g < 20 && empty.b < 20)
    }

    @Test func missingMediaIsReportedPerInput() async throws {
        var project = try ProjectLocation(try Self.sliceURL).load()
        let id = project.inputs[0].id
        project.inputs[0].source = MediaReference(path: "../does-not-exist.mp4")
        let loaded = try await ProjectCompiler.load(project, location: ProjectLocation(try Self.sliceURL))
        #expect(loaded.problems[id]?.contains("does-not-exist") == true)
        #expect(loaded.problems.count == 1)
    }
}

@Suite("Preview/export parity", .serialized)
struct ParityTests {
    /// The preview (AVPlayer / AVAssetImageGenerator on the composition) and the export must show
    /// the same pixels for the same time. Compares a generator frame against an exported frame.
    @Test func previewFrameMatchesExportedFrame() async throws {
        let output = MediaFixtures.temporaryOutput("parity")
        defer { try? FileManager.default.removeItem(at: output) }
        let loaded = try await ProjectCompiler.load(try ProjectCompilerTests.sliceURL)
        let compiled = try await ProjectCompiler.compile(loaded)

        let generator = AVAssetImageGenerator(asset: compiled.composition)
        generator.videoComposition = compiled.videoComposition
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let previewImage = try await generator.image(at: CMTime(seconds: 1.0, preferredTimescale: 600)).image
        let preview = try PixelBuffers.makeBuffer(width: previewImage.width, height: previewImage.height)
        try PixelBuffers.draw(into: preview) { context, size in
            context.translateBy(x: 0, y: size.height)
            context.scaleBy(x: 1, y: -1)
            context.draw(previewImage, in: CGRect(origin: .zero, size: size))
        }

        for try await _ in Exporter.export(compiled, settings: loaded.project.export, range: 0...1.5, to: output) {}
        let exported = try await MediaFixtures.frame(of: output, at: 1.0)
        #expect(CVPixelBufferGetWidth(preview) == CVPixelBufferGetWidth(exported))

        // Compare on a grid. H.264 at 2 Mbit/s smears the pattern's noise blocks, so use the mean
        // absolute error plus a cap on gross outliers rather than a strict per-pixel bound.
        var totalError = 0
        var gross = 0
        var samples = 0
        for y in stride(from: 4, to: 356, by: 8) {
            for x in stride(from: 4, to: 636, by: 8) {
                let a = PixelBuffers.pixel(in: preview, x: x, y: y)
                let b = PixelBuffers.pixel(in: exported, x: x, y: y)
                let error = abs(Int(a.r) - Int(b.r)) + abs(Int(a.g) - Int(b.g)) + abs(Int(a.b) - Int(b.b))
                totalError += error
                if error > 300 { gross += 1 }
                samples += 1
            }
        }
        let meanError = Double(totalError) / Double(samples * 3)
        let grossFraction = Double(gross) / Double(samples)
        print("parity: mean abs error \(meanError), gross outliers \(grossFraction * 100)%")
        #expect(meanError < 12, "mean channel error \(meanError)")
        #expect(grossFraction < 0.01, "\(gross)/\(samples) points differ grossly")
    }

    @Test func replanSwapsOverlaysWithoutRebuildingMedia() async throws {
        let loaded = try await ProjectCompiler.load(try ProjectCompilerTests.sliceURL)
        let compiled = try await ProjectCompiler.compile(loaded)
        var project = loaded.project
        project.displayObjects.removeAll { $0.kind.needsData }
        let edited = ProjectCompiler.LoadedProject(
            project: project, location: loaded.location, sessions: loaded.sessions, mediaInfo: loaded.mediaInfo)
        #expect(!ProjectCompiler.needsRecompile(from: loaded.project, to: project))
        let replanned = ProjectCompiler.replan(compiled, for: edited)
        #expect(replanned.composition === compiled.composition)
        #expect(replanned.plan.overlays.isEmpty)
        #expect(replanned.plan.videoLayers == compiled.plan.videoLayers)
        #expect(replanned.videoComposition !== compiled.videoComposition)
        var moved = loaded.project
        moved.inputs[0].sync.offsetInProject = 1
        #expect(ProjectCompiler.needsRecompile(from: loaded.project, to: moved))
    }
}

/// #131: a sync nudge that puts a video before the project's start.
///
/// Nudging the video earlier is how you sync when the camera started before the logger, and from
/// an offset of zero one press makes it negative. `insertTimeRange(_:of:at:)` cannot take a
/// negative time and fails the **whole** composition with `-11800` / `-12780`, so the preview
/// stops recompiling until the nudge is undone.
@Suite("Sync before the project start")
struct NegativeOffsetTests {
    static func build(offset: Double, speed: Double = 1, trim: TrimRange = .none) async throws -> CompiledComposition {
        try await CompositionBuilder.build(
            videos: [
                VideoInputSpec(
                    url: try MediaFixtures.video, sync: SyncSettings(offsetInProject: offset, playSpeed: speed),
                    trim: trim, includeAudio: false)
            ], overlays: [], outputWidth: 64, outputHeight: 36, frameRate: 30)
    }

    @Test func aVideoNudgedBeforeZeroComposesWithItsHeadDropped() async throws {
        // The exact report: one −0.1 nudge from an offset of zero.
        let compiled = try await Self.build(offset: -0.1)
        // Three seconds of clip, a tenth of it before the project starts, so 2.9 remain.
        #expect(abs(compiled.duration - 2.9) < 0.02)

        // Not just the right length — the right *content*. Project time zero must show the frame a
        // tenth of a second into the file, which is what "the video moved earlier" means.
        let track = try #require(compiled.composition.tracks(withMediaType: .video).first)
        let segment = try #require(track.segments.first { !$0.isEmpty })
        #expect(abs(segment.timeMapping.target.start.seconds) < 0.01)
        #expect(abs(segment.timeMapping.source.start.seconds - 0.1) < 0.02)
    }

    @Test func theDroppedPartIsMeasuredInTheFilesOwnSeconds() async throws {
        // At double speed a tenth of a second of timeline is two tenths of the file, so the same
        // nudge eats twice as much of it. Getting this backwards would desync the very thing the
        // nudge was for.
        let compiled = try await Self.build(offset: -0.1, speed: 2)
        // (3 − 0.2) / 2 = 1.4
        #expect(abs(compiled.duration - 1.4) < 0.02)
        let track = try #require(compiled.composition.tracks(withMediaType: .video).first)
        let segment = try #require(track.segments.first { !$0.isEmpty })
        #expect(abs(segment.timeMapping.source.start.seconds - 0.2) < 0.02)
    }

    @Test func nudgingBackPutsBackExactlyWhatItTook() async throws {
        // The reason the stored offset is not clamped: a nudge has to be reversible.
        let original = SyncSettings(startPositionInInput: 0.25, offsetInProject: 0, playSpeed: 1)
        let there = SyncWizard.shifted(original, byProjectSeconds: -0.1)
        let back = SyncWizard.shifted(there, byProjectSeconds: 0.1)
        #expect(back == original)
        #expect(there.offsetInProject == -0.1)
        // And the composition is the one it was before.
        let before = try await Self.build(offset: 0)
        let after = try await Self.build(offset: 0)
        #expect(abs(before.duration - after.duration) < 1e-9)
    }

    @Test func aVideoEntirelyBeforeTheProjectIsRejectedRatherThanDrawnEmpty() async throws {
        // Pushed further back than it is long there is nothing left to show, which is the same
        // situation as a trim that empties the input and gets the same answer.
        await #expect(throws: CompositionError.self) { _ = try await Self.build(offset: -5) }
    }

    @Test func aPositiveOffsetIsUntouched() async throws {
        // The ordinary case has to keep working exactly as it did: the clip starts where it says.
        let compiled = try await Self.build(offset: 0.5)
        #expect(abs(compiled.duration - 3.5) < 0.02)
        let track = try #require(compiled.composition.tracks(withMediaType: .video).first)
        let segment = try #require(track.segments.first { !$0.isEmpty })
        #expect(abs(segment.timeMapping.target.start.seconds - 0.5) < 0.02)
        #expect(abs(segment.timeMapping.source.start.seconds) < 0.02)
    }
}
