import AVFoundation
import Foundation
import Testing

@testable import MediaKit
@testable import ProjectModel
@testable import RenderKit
@testable import TelemetryKit

@Suite("Export options", .serialized)
struct ExportOptionsTests {
    /// A 3 s video with a synthetic data input whose laps are 0.5–1.5 s and 1.5–2.5 s in data
    /// time, offset so data time 0 is project time 0.25.
    func loadedProject() async throws -> ProjectCompiler.LoadedProject {
        let video = Input(
            label: "v", source: MediaReference(path: try MediaFixtures.video.path), kind: .video(VideoInputSettings()))
        var data = Input(label: "d", source: MediaReference(path: "unused.csv"), kind: .data(DataInputSettings()))
        data.sync = SyncSettings(startPositionInInput: 0, offsetInProject: 0.25, playSpeed: 1)
        var project = Project(
            inputs: [video, data],
            displayObjects: [
                DisplayObject(label: "v", inputID: video.id, frame: .full, kind: .video(VideoObjectParams())),
                DisplayObject(
                    label: "shape", inputID: nil, frame: UnitRect(x: 0.6, y: 0.6, width: 0.3, height: 0.3),
                    kind: .shape(ShapeParams(shape: .rectangle, fillColor: .white, strokeWidth: 0))),
            ])
        project.settings.outputWidth = 320
        project.settings.outputHeight = 180
        let location = ProjectLocation(URL(fileURLWithPath: "/tmp/x.overlayproj"))
        var loaded = try await ProjectCompiler.load(project, location: location)
        // The CSV does not exist; substitute a synthetic session as if it had loaded.
        loaded.problems[data.id] = nil
        loaded.sessions[data.id] = TelemetrySession(
            info: SessionInfo(sourceFormat: "test"),
            channels: [Channel(role: .speed, name: "s", unit: .metersPerSecond, times: [0, 3], values: [1, 1])],
            laps: [
                Lap(number: 1, start: 0.5, end: 1.5, isComplete: true),
                Lap(number: 2, start: 1.5, end: 2.5, isComplete: true),
            ])
        return loaded
    }

    @Test func missingFilesAreProblemsNotFailures() async throws {
        let loaded = try await loadedProject()
        // Reload from the same project: the data file is missing, the video is fine.
        let fresh = try await ProjectCompiler.load(loaded.project, location: loaded.location)
        #expect(fresh.problems.count == 1)
        #expect(fresh.problems.values.first?.contains("File not found") == true)
        #expect(fresh.mediaInfo.count == 1)
        // A missing video is skipped; with none left, compile says so.
        var broken = loaded.project
        broken.inputs[0].source = MediaReference(path: "/nowhere/missing.mp4")
        let none = try await ProjectCompiler.load(broken, location: loaded.location)
        #expect(none.problems.count == 2)
        await #expect(throws: ProjectCompiler.LoadError.self) { try await ProjectCompiler.compile(none) }
    }

    @Test func lapRangesMapThroughSync() async throws {
        let loaded = try await loadedProject()
        let both = ProjectCompiler.exportRange(.laps(first: 1, last: 2), in: loaded, duration: 3)
        #expect(both?.lowerBound == 0.75 && both?.upperBound == 2.75)
        let second = ProjectCompiler.exportRange(.laps(first: 2, last: 2), in: loaded, duration: 3)
        #expect(second?.lowerBound == 1.75 && second?.upperBound == 2.75)
        #expect(ProjectCompiler.exportRange(.laps(first: 7, last: 9), in: loaded, duration: 3) == nil)
        #expect(ProjectCompiler.exportRange(.span(start: 1, end: 10), in: loaded, duration: 3) == 1...3)
        #expect(ProjectCompiler.exportRange(.whole, in: loaded, duration: 3) == nil)
    }

    @Test func lapRangeExportHasTheLapDuration() async throws {
        let output = MediaFixtures.temporaryOutput("laps")
        defer { try? FileManager.default.removeItem(at: output) }
        let loaded = try await loadedProject()
        let compiled = try await ProjectCompiler.compile(loaded)
        let range = try #require(
            ProjectCompiler.exportRange(.laps(first: 2, last: 2), in: loaded, duration: compiled.duration))
        var settings = ExportSettings(width: 320, height: 180, frameRate: 30, videoBitrate: 1_000_000)
        settings.audioBitrate = nil
        for try await _ in Exporter.export(compiled, settings: settings, range: range, to: output) {}
        let duration = try await AVURLAsset(url: output).load(.duration).seconds
        #expect(abs(duration - 1.0) < 0.07)
    }

    @Test func keyColourExportHasNoVideo() async throws {
        let output = MediaFixtures.temporaryOutput("keyed")
        defer { try? FileManager.default.removeItem(at: output) }
        let loaded = try await loadedProject()
        var settings = ExportSettings.overlayKeyed
        settings.width = 320
        settings.height = 180
        settings.frameRate = 30
        let compiled = ProjectCompiler.prepareForExport(try await ProjectCompiler.compile(loaded), settings: settings)
        #expect(compiled.plan.videoLayers.isEmpty)
        for try await _ in Exporter.export(compiled, settings: settings, range: 0...1, to: output) {}
        let frame = try await MediaFixtures.frame(of: output, at: 0.5)
        let background = PixelBuffers.pixel(in: frame, x: 40, y: 40)
        #expect(Int(background.b) > 200 && Int(background.r) < 40 && Int(background.g) < 40)
        let shape = PixelBuffers.pixel(in: frame, x: 240, y: 135)
        #expect(Int(shape.r) > 200 && Int(shape.g) > 200)
    }

    @Test func transparentProResExportKeepsAlpha() async throws {
        let output = MediaFixtures.temporaryOutput("alpha").deletingPathExtension().appendingPathExtension("mov")
        defer { try? FileManager.default.removeItem(at: output) }
        let loaded = try await loadedProject()
        var settings = ExportSettings.overlayAlpha
        settings.width = 320
        settings.height = 180
        settings.frameRate = 30
        let compiled = ProjectCompiler.prepareForExport(try await ProjectCompiler.compile(loaded), settings: settings)
        for try await _ in Exporter.export(compiled, settings: settings, range: 0...1, to: output) {}
        let asset = AVURLAsset(url: output)
        let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
        let descriptions = try await track.load(.formatDescriptions)
        let codec = descriptions.first.map { CMFormatDescriptionGetMediaSubType($0) }
        #expect(codec == kCMVideoCodecType_AppleProRes4444)
        // Read a frame with alpha: the empty area is transparent, the shape is opaque.
        let reader = try AVAssetReader(asset: asset)
        let readerOutput = AVAssetReaderTrackOutput(
            track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        reader.add(readerOutput)
        reader.startReading()
        var buffer: CVPixelBuffer?
        while let sample = readerOutput.copyNextSampleBuffer() {
            if CMSampleBufferGetPresentationTimeStamp(sample).seconds >= 0.5 {
                buffer = CMSampleBufferGetImageBuffer(sample)
                break
            }
        }
        let frame = try #require(buffer)
        #expect(PixelBuffers.pixel(in: frame, x: 40, y: 40).a < 8)
        #expect(PixelBuffers.pixel(in: frame, x: 240, y: 135).a > 240)
    }
}
