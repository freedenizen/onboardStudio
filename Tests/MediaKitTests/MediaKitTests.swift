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
        FileManager.default.temporaryDirectory.appending(path: "overlaygen-\(name)-\(UUID().uuidString).mp4")
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
