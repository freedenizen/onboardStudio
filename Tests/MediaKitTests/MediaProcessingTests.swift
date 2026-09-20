import AVFoundation
import Foundation
import Testing

@testable import MediaKit
@testable import ProjectModel
@testable import RenderKit

@Suite("Audio processing", .serialized)
struct AudioProcessingTests {
    @Test func channelGainsFollowBalanceAndSelection() {
        let centre = ChannelGains(balance: 0, channels: .stereo)
        #expect(abs(centre.leftFromLeft - 1) < 1e-6 && abs(centre.rightFromRight - 1) < 1e-6)
        #expect(centre.leftFromRight == 0 && centre.rightFromLeft == 0)
        let hardLeft = ChannelGains(balance: -1, channels: .stereo)
        #expect(hardLeft.rightFromRight < 1e-6 && hardLeft.leftFromLeft > 1.4)
        let leftOnly = ChannelGains(balance: 0, channels: .left)
        #expect(leftOnly.rightFromLeft > 0.99 && leftOnly.rightFromRight == 0)
        let mono = ChannelGains(balance: 0, channels: .mono)
        #expect(abs(mono.leftFromLeft - 0.5) < 1e-6 && abs(mono.leftFromRight - 0.5) < 1e-6)
    }

    @Test func applyMixesInterleavedAndPlanarBuffers() {
        let gains = ChannelGains(balance: 0, channels: .left)
        var interleaved: [Float] = [1, 0, 1, 0, 1, 0]  // L=1, R=0 × 3 frames
        interleaved.withUnsafeMutableBufferPointer { buffer in
            var list = AudioBufferList(
                mNumberBuffers: 1,
                mBuffers: AudioBuffer(
                    mNumberChannels: 2, mDataByteSize: UInt32(buffer.count * 4),
                    mData: UnsafeMutableRawPointer(buffer.baseAddress)))
            AudioTap.apply(gains, to: &list, frames: 3, channels: 2, interleaved: true)
        }
        #expect(interleaved[1] > 0.99 && interleaved[3] > 0.99)  // right channel now carries left
    }

    /// Exports the stereo fixture with "left only" and checks the right channel now carries the
    /// 440 Hz tone (via ffmpeg's astats), skipping when ffmpeg is unavailable.
    @Test func exportAppliesChannelSelection() async throws {
        guard let ffmpeg = FFmpegBridge.executable else { return }
        let fixture = try #require(Bundle.module.url(forResource: "Fixtures", withExtension: nil)).appending(
            path: "stereo-1s.mp4")
        let output = MediaFixtures.temporaryOutput("audio")
        defer { try? FileManager.default.removeItem(at: output) }
        let spec = VideoInputSpec(url: fixture, audio: AudioSettings(volume: 1, balance: 0, channels: .left))
        let compiled = try await CompositionBuilder.build(
            videos: [spec], overlays: [], outputWidth: 160, outputHeight: 90, frameRate: 25)
        #expect(compiled.audioMix != nil)
        for try await _ in Exporter.export(
            compiled, settings: ExportSettings(width: 160, height: 90, frameRate: 25, videoBitrate: 300_000), to: output
        ) {}
        // Measure the dominant frequency per channel with ffmpeg's aspectralstats would be heavy;
        // instead compare RMS: the right channel originally carried 880 Hz at the same level, so
        // after "left only" both channels must have similar RMS and be non-silent.
        let process = Process()
        process.executableURL = ffmpeg
        process.arguments = ["-hide_banner", "-i", output.path, "-af", "astats=metadata=1:reset=0", "-f", "null", "-"]
        let pipe = Pipe()
        process.standardError = pipe
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        let text = String(bytes: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let rms = text.components(separatedBy: "\n").filter { $0.contains("RMS level dB") }.compactMap {
            line -> Double? in
            Double(line.split(separator: ":").last?.trimmingCharacters(in: .whitespaces) ?? "")
        }
        #expect(rms.count >= 2, "expected per-channel RMS lines, got \(rms)")
        if rms.count >= 2 {
            #expect(rms[0] > -30 && rms[1] > -30, "both channels should carry the tone: \(rms)")
            #expect(abs(rms[0] - rms[1]) < 3, "left-only should copy L to R: \(rms)")
        }
    }

    @Test func mutedInputProducesSilence() async throws {
        let fixture = try #require(Bundle.module.url(forResource: "Fixtures", withExtension: nil)).appending(
            path: "stereo-1s.mp4")
        let spec = VideoInputSpec(url: fixture, audio: AudioSettings(isMuted: true))
        let compiled = try await CompositionBuilder.build(
            videos: [spec], overlays: [], outputWidth: 160, outputHeight: 90, frameRate: 25)
        let mix = try #require(compiled.audioMix)
        #expect(mix.inputParameters.count == 1)
    }
}

@Suite("FFmpeg bridge", .serialized)
struct FFmpegBridgeTests {
    @Test func readableFilesPassThrough() async throws {
        let url = try MediaFixtures.video
        #expect(try await FFmpegBridge.prepare(url) == url)
    }

    @Test func transportStreamIsRemuxedWhenFFmpegExists() async throws {
        let mts = try #require(Bundle.module.url(forResource: "Fixtures", withExtension: nil)).appending(
            path: "test-1s.mts")
        let readable = (try? await AVURLAsset(url: mts).load(.isReadable)) ?? false
        let hasVideo = !((try? await AVURLAsset(url: mts).loadTracks(withMediaType: .video)) ?? []).isEmpty
        if readable && hasVideo {
            // This macOS can read MPEG-TS natively; nothing to convert.
            #expect(try await FFmpegBridge.prepare(mts) == mts)
            return
        }
        guard FFmpegBridge.executable != nil else {
            await #expect(throws: FFmpegBridge.PrepareError.self) { _ = try await FFmpegBridge.prepare(mts) }
            return
        }
        let converted = try await FFmpegBridge.prepare(mts)
        defer { try? FileManager.default.removeItem(at: converted) }
        #expect(converted != mts && converted.pathExtension == "mov")
        let info = try await MediaProbe.probe(converted)
        #expect(info.width == 320 && info.height == 180)
        #expect(abs(info.duration - 1) < 0.15)
        // Second call hits the cache.
        #expect(try await FFmpegBridge.prepare(mts) == converted)
    }

    @Test func cacheNameIsStableAndDistinct() {
        let a = FFmpegBridge.cacheName(for: URL(fileURLWithPath: "/tmp/a.mts"))
        #expect(a == FFmpegBridge.cacheName(for: URL(fileURLWithPath: "/tmp/a.mts")))
        #expect(a != FFmpegBridge.cacheName(for: URL(fileURLWithPath: "/tmp/b.mts")))
        #expect(a.hasSuffix(".mov"))
    }
}

@Suite("Recompile decisions")
struct RecompileTests {
    @Test func pictureEditsReplanButTimingAndAudioRecompile() throws {
        var base = try ProjectLocation(try ProjectCompilerTests.sliceURL).load()
        guard case .video(var settings) = base.inputs[0].kind else { return }
        var picture = base
        settings.rotation = 90
        settings.color.saturation = 0
        picture.inputs[0].kind = .video(settings)
        #expect(!ProjectCompiler.needsRecompile(from: base, to: picture))
        var audio = base
        var audioSettings = settings
        audioSettings.audio.balance = 0.5
        audio.inputs[0].kind = .video(audioSettings)
        #expect(ProjectCompiler.needsRecompile(from: base, to: audio))
        base.inputs[0].sync.playSpeed = 2
        #expect(ProjectCompiler.needsRecompile(from: picture, to: base))
    }
}

@Suite("Source orientation", .serialized)
struct SourceOrientationMediaTests {
    static var rotated: URL {
        get throws {
            try #require(Bundle.module.url(forResource: "Fixtures", withExtension: nil)).appending(
                path: "test-rot180.mp4")
        }
    }

    @Test func preferredTransformIsCapturedAsSourceTransform() async throws {
        let compiled = try await CompositionBuilder.build(
            videos: [VideoInputSpec(url: try Self.rotated)], overlays: [], outputWidth: 320, outputHeight: 180,
            frameRate: 25)
        let layer = try #require(compiled.plan.videoLayers.first)
        #expect(abs(layer.sourceTransform.a + 1) < 1e-6 && abs(layer.sourceTransform.d + 1) < 1e-6)
        #expect(abs(layer.sourceTransform.b) < 1e-6 && abs(layer.sourceTransform.c) < 1e-6)
        let plain = try await CompositionBuilder.build(
            videos: [VideoInputSpec(url: try MediaFixtures.video)], overlays: [], outputWidth: 320, outputHeight: 180,
            frameRate: 25)
        #expect(plain.plan.videoLayers.first?.sourceTransform == .identity)
    }

    @Test func replanKeepsTheSourceTransform() async throws {
        let video = Input(
            label: "v", source: MediaReference(path: try Self.rotated.path), kind: .video(VideoInputSettings()))
        var project = Project(
            inputs: [video],
            displayObjects: [
                DisplayObject(label: "v", inputID: video.id, frame: .full, kind: .video(VideoObjectParams()))
            ])
        project.settings.outputWidth = 320
        project.settings.outputHeight = 180
        let location = ProjectLocation(URL(fileURLWithPath: "/tmp/x.onboardproj"))
        let loaded = try await ProjectCompiler.load(project, location: location)
        let compiled = try await ProjectCompiler.compile(loaded)
        #expect(compiled.plan.videoLayers.first?.sourceTransform != .identity)
        // An object edit goes through replan; the rotation must survive it.
        project.displayObjects[0].opacity = 0.5
        let replanned = ProjectCompiler.replan(
            compiled, for: try await ProjectCompiler.load(project, location: location, reusing: loaded))
        #expect(replanned.plan.videoLayers.first?.sourceTransform == compiled.plan.videoLayers.first?.sourceTransform)
        #expect(replanned.plan.videoLayers.first?.opacity == 0.5)
    }

    /// Our export must show the clip the way macOS shows it (AVAssetImageGenerator applies the
    /// preferred transform), i.e. upside down relative to the encoded pixels.
    @Test func exportMatchesSystemOrientation() async throws {
        let output = MediaFixtures.temporaryOutput("rot180")
        defer { try? FileManager.default.removeItem(at: output) }
        let url = try Self.rotated
        let compiled = try await CompositionBuilder.build(
            videos: [VideoInputSpec(url: url)], overlays: [], outputWidth: 320, outputHeight: 180, frameRate: 25)
        for try await _ in Exporter.export(
            compiled,
            settings: ExportSettings(width: 320, height: 180, frameRate: 25, videoBitrate: 800_000, audioBitrate: nil),
            to: output)
        {}
        let ours = try await MediaFixtures.frame(of: output, at: 0.5)
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let systemImage = try await generator.image(at: CMTime(seconds: 0.5, preferredTimescale: 600)).image
        let system = try PixelBuffers.makeBuffer(width: systemImage.width, height: systemImage.height)
        try PixelBuffers.draw(into: system) { context, size in
            context.translateBy(x: 0, y: size.height)
            context.scaleBy(x: 1, y: -1)
            context.draw(systemImage, in: CGRect(origin: .zero, size: size))
        }
        var total = 0
        var samples = 0
        for y in stride(from: 6, to: 174, by: 12) {
            for x in stride(from: 6, to: 314, by: 12) {
                let a = PixelBuffers.pixel(in: ours, x: x, y: y)
                let b = PixelBuffers.pixel(in: system, x: x, y: y)
                total += abs(Int(a.r) - Int(b.r)) + abs(Int(a.g) - Int(b.g)) + abs(Int(a.b) - Int(b.b))
                samples += 1
            }
        }
        let mean = Double(total) / Double(samples * 3)
        #expect(mean < 14, "mean channel difference vs. the system-oriented frame: \(mean)")
        // Sanity: the encoded (un-rotated) frame must differ from ours, otherwise the test proves nothing.
        var unrotatedTotal = 0
        let plainGenerator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        plainGenerator.appliesPreferredTrackTransform = false
        plainGenerator.requestedTimeToleranceBefore = .zero
        plainGenerator.requestedTimeToleranceAfter = .zero
        let rawImage = try await plainGenerator.image(at: CMTime(seconds: 0.5, preferredTimescale: 600)).image
        let raw = try PixelBuffers.makeBuffer(width: rawImage.width, height: rawImage.height)
        try PixelBuffers.draw(into: raw) { context, size in
            context.translateBy(x: 0, y: size.height)
            context.scaleBy(x: 1, y: -1)
            context.draw(rawImage, in: CGRect(origin: .zero, size: size))
        }
        for y in stride(from: 6, to: 174, by: 12) {
            for x in stride(from: 6, to: 314, by: 12) {
                let a = PixelBuffers.pixel(in: ours, x: x, y: y)
                let b = PixelBuffers.pixel(in: raw, x: x, y: y)
                unrotatedTotal += abs(Int(a.r) - Int(b.r)) + abs(Int(a.g) - Int(b.g)) + abs(Int(a.b) - Int(b.b))
            }
        }
        #expect(
            Double(unrotatedTotal) / Double(samples * 3) > 30,
            "the rotated fixture should not match the un-rotated pixels")
    }
}
