import ArgumentParser
import Foundation
import MediaKit
import ProjectModel
import RenderKit

struct Render: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Render a video through the OverlayGen pipeline with a burned-in timestamp.",
        discussion: """
            Re-encodes the input video via the same AVFoundation composition and custom compositor the
            app uses for preview and export. Useful for verifying the pipeline and for sync checks.
            """)

    @Option(name: .long, help: "Input video file (MP4/MOV). Mutually exclusive with --project.")
    var video: String?

    @Option(name: .long, help: "An .overlayproj package or project.json to render with all its display objects.")
    var project: String?

    @Option(name: .long, help: "Output .mp4 path.")
    var out: String

    @Option(name: .long, help: "Project time range to export as start:end seconds, e.g. 0:3.")
    var range: String?

    @Option(name: .long, help: "Output preset: 720p, 1080p, 4k. Defaults to the input's size.")
    var preset: String?

    @Option(name: .long, help: "Output width in pixels (overrides preset).")
    var width: Int?

    @Option(name: .long, help: "Output height in pixels (overrides preset).")
    var height: Int?

    @Option(name: .long, help: "Output frame rate. Defaults to the input's.")
    var fps: Double?

    @Option(name: .long, help: "Video codec: h264 or hevc.")
    var codec: ExportSettings.VideoCodec?

    @Option(name: .long, help: "Video bitrate in kbit/s.")
    var bitrate: Int?

    @Option(name: .long, help: "Seconds into the input video where project time 0 starts.")
    var startPosition: Double = 0

    @Option(name: .long, help: "Playback speed multiplier (1 = normal, 2 = double).")
    var speed: Double = 1

    @Flag(name: .long, help: "Drop the audio track.")
    var noAudio = false

    @Flag(name: .long, help: "Do not draw the timestamp overlay.")
    var noTimestamp = false

    @Flag(name: .long, help: "Print progress as JSON lines.")
    var json = false

    func run() async throws {
        let outputURL = URL(fileURLWithPath: out)
        let exportRange = try range.map(Self.parseRange)
        let compiled: CompiledComposition
        let settings: ExportSettings
        if let project {
            guard video == nil else { throw ValidationError("Use either --video or --project, not both.") }
            let loaded = try await ProjectCompiler.load(URL(fileURLWithPath: project))
            compiled = try await ProjectCompiler.compile(loaded)
            settings = resolveProjectSettings(loaded.project)
            if !json {
                let objects = loaded.project.displayObjects.map(\.kind.typeName).joined(separator: ", ")
                let counts = "\(loaded.project.inputs.count) inputs, \(loaded.sessions.count) data sessions"
                print("Project:  \(counts); objects: \(objects)")
            }
        } else {
            guard let video else { throw ValidationError("Provide --video or --project.") }
            let inputURL = URL(fileURLWithPath: video)
            let info = try await MediaProbe.probe(inputURL)
            guard info.hasVideo else { throw ValidationError("\(video) has no video track.") }
            settings = try resolveSettings(info: info)
            let spec = VideoInputSpec(
                url: inputURL, sync: SyncSettings(startPositionInInput: startPosition, playSpeed: speed),
                includeAudio: !noAudio)
            let overlays: [any OverlayDrawing] =
                noTimestamp ? [] : [TimestampOverlay(label: inputURL.lastPathComponent)]
            compiled = try await CompositionBuilder.build(
                videos: [spec], overlays: overlays, outputWidth: settings.width, outputHeight: settings.height,
                frameRate: settings.frameRate)
            if !json {
                let inputSize = "\(info.width)x\(info.height) @ \(fmt(info.nominalFrameRate)) fps"
                print("Input:    \(inputURL.lastPathComponent)  \(inputSize), \(fmt(info.duration)) s")
            }
        }

        if !json {
            let outputSize = "\(settings.width)x\(settings.height) @ \(fmt(settings.frameRate)) fps"
            let encoding = "\(settings.codec.rawValue) \(settings.videoBitrate / 1000) kbit/s"
            print("Output:   \(outputURL.lastPathComponent)  \(outputSize), \(encoding)")
            let rangeText = exportRange.map { ", exporting \(fmt($0.lowerBound))–\(fmt($0.upperBound)) s" } ?? ""
            print("Project:  \(fmt(compiled.duration)) s\(rangeText)")
        }

        let started = Date()
        var lastPrinted = -1
        var frames = 0
        for try await progress in Exporter.export(compiled, settings: settings, range: exportRange, to: outputURL) {
            frames = progress.framesWritten
            if json {
                let line = #"{"fraction":\#(progress.fraction),"frames":\#(progress.framesWritten),"#
                print(line + #""time":\#(progress.currentTime)}"#)
            } else {
                let percent = Int(progress.fraction * 100)
                if percent / 10 != lastPrinted / 10 {
                    print("  \(percent)%  (\(progress.framesWritten) frames)")
                    lastPrinted = percent
                }
            }
        }
        let elapsed = Date().timeIntervalSince(started)
        let fps = elapsed > 0 ? Double(frames) / elapsed : 0
        if !json { print("Done: \(frames) frames in \(fmt(elapsed)) s (\(fmt(fps)) fps) → \(out)") }
    }

    /// Project export settings with CLI overrides applied.
    private func resolveProjectSettings(_ project: Project) -> ExportSettings {
        var settings = project.export
        settings.width = width ?? project.settings.outputWidth
        settings.height = height ?? project.settings.outputHeight
        settings.frameRate = fps ?? project.settings.frameRate
        if let codec { settings.codec = codec }
        if let bitrate { settings.videoBitrate = bitrate * 1000 }
        if noAudio { settings.audioBitrate = nil }
        settings.width -= settings.width % 2
        settings.height -= settings.height % 2
        return settings
    }

    /// Combines the preset, explicit overrides and the input's own properties into export settings.
    private func resolveSettings(info: MediaInfo) throws -> ExportSettings {
        var settings = ExportSettings(width: info.width, height: info.height)
        if let preset {
            guard let chosen = ExportSettings.presets[preset.lowercased()] else {
                let names = ExportSettings.presets.keys.sorted().joined(separator: ", ")
                throw ValidationError("Unknown preset '\(preset)'. Use one of: \(names)")
            }
            settings = chosen
        }
        if let width { settings.width = width }
        if let height { settings.height = height }
        settings.frameRate = fps ?? (info.nominalFrameRate > 0 ? info.nominalFrameRate : 30)
        if let codec { settings.codec = codec }
        if let bitrate { settings.videoBitrate = bitrate * 1000 }
        if noAudio { settings.audioBitrate = nil }
        settings.width -= settings.width % 2
        settings.height -= settings.height % 2
        return settings
    }

    static func parseRange(_ text: String) throws -> ClosedRange<Double> {
        let parts = text.split(separator: ":").map { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count == 2, let start = parts[0], let end = parts[1], end > start, start >= 0 else {
            throw ValidationError("Range must be start:end in seconds with end > start, e.g. 0:3.")
        }
        return start...end
    }

    private func fmt(_ value: Double) -> String {
        value == value.rounded() ? String(format: "%.0f", value) : String(format: "%.2f", value)
    }
}

extension ExportSettings.VideoCodec: ExpressibleByArgument {}
