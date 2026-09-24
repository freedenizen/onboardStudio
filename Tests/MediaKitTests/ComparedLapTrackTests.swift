import AVFoundation
import Foundation
import ProjectModel
import TelemetryKit
import Testing

@testable import MediaKit
@testable import RenderKit

@Suite("The compared lap's picture (#154)", .serialized)
struct ComparedLapTrackTests {
    /// The fixture video with a data input whose lap 1 (0–1 s) is twice as fast as lap 2 (1–3 s),
    /// laid out as a comparison of lap 2 (left) with lap 1 (right).
    func comparingProject() async throws -> ProjectCompiler.LoadedProject {
        let video = Input(
            label: "v", source: MediaReference(path: try MediaFixtures.video.path), kind: .video(VideoInputSettings()))
        let data = Input(label: "d", source: MediaReference(path: "unused.csv"), kind: .data(DataInputSettings()))
        var project = Project(
            inputs: [video, data],
            displayObjects: [
                DisplayObject(
                    label: "Lap", inputID: video.id, frame: UnitRect(x: 0, y: 0, width: 0.5, height: 1),
                    kind: .video(VideoObjectParams())),
                DisplayObject(
                    label: "Compared", inputID: video.id, frame: UnitRect(x: 0.5, y: 0, width: 0.5, height: 1),
                    kind: .video(VideoObjectParams()), followsComparedLap: true),
            ])
        project.settings.outputWidth = 320
        project.settings.outputHeight = 180
        project.lapComparison = LapComparisonSettings(
            lap: .init(dataInputID: data.id, videoInputID: video.id, lap: 2),
            comparedLap: .init(dataInputID: data.id, videoInputID: video.id, lap: 1))
        var loaded = try await ProjectCompiler.load(
            project, location: ProjectLocation(URL(fileURLWithPath: "/tmp/x.onboardproj")))
        loaded.problems[data.id] = nil
        loaded.sessions[data.id] = Self.session
        return loaded
    }

    static let session: TelemetrySession = {
        let times = Array(stride(from: 0.0, through: 3.0, by: 0.05))
        return TelemetrySession(
            info: SessionInfo(sourceFormat: "test"),
            channels: [
                Channel(
                    role: .distance, name: "d", unit: .meters, times: times,
                    values: times.map { $0 < 1 ? 100 * $0 : 100 + 50 * ($0 - 1) })
            ],
            laps: [
                Lap(number: 1, start: 0, end: 1, isComplete: true), Lap(number: 2, start: 1, end: 3, isComplete: true),
            ])
    }()

    @Test func aComparingProjectCompilesTheComparedTrackAndExportsBothPictures() async throws {
        let loaded = try await comparingProject()
        let compiled = try await ProjectCompiler.compile(loaded)
        let compared = try #require(compiled.comparedTrackID)
        #expect(compiled.plan.videoLayers.map(\.trackID) == [compiled.trackIDs[0], compared])
        // Every instruction asks for it, so AVFoundation decodes it throughout.
        for case let instruction as OverlayInstruction in compiled.videoComposition.instructions {
            #expect(instruction.requiredSourceTrackIDs?.contains(NSNumber(value: compared)) == true)
        }
        let output = MediaFixtures.temporaryOutput("compare")
        defer { try? FileManager.default.removeItem(at: output) }
        var settings = ExportSettings(width: 320, height: 180, frameRate: 30, videoBitrate: 1_000_000)
        settings.audioBitrate = nil
        for try await _ in Exporter.export(compiled, settings: settings, range: 1...3, to: output) {}
        let frame = try await MediaFixtures.frame(of: output, at: 1)
        // Both halves carry a picture, not the black of an empty track.
        for x in [80, 240] {
            let pixel = PixelBuffers.pixel(in: frame, x: x, y: 90)
            #expect(Int(pixel.r) + Int(pixel.g) + Int(pixel.b) > 60, "x \(x): \(pixel)")
        }
        // Changing the laps compared rebuilds the media, since the track is cut to them.
        var other = loaded.project
        other.lapComparison?.comparedLap.lap = 2
        #expect(ProjectCompiler.needsRecompile(from: loaded.project, to: other))
    }

    @Test func theTrackShowsTheMomentTheWarpNames() async throws {
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Fixtures/test-3s.mp4")
        // Lap 1 (0–1 s) covers 100 m at 100 m/s, lap 2 (1–3 s) the same 100 m at 50 m/s: comparing
        // lap 2 with lap 1 plays the first second of the file over the last two of the project.
        let times = Array(stride(from: 0.0, through: 3.0, by: 0.05))
        let session = TelemetrySession(
            info: SessionInfo(sourceFormat: "test"),
            channels: [
                Channel(
                    role: .distance, name: "d", unit: .meters, times: times,
                    values: times.map { $0 < 1 ? 100 * $0 : 100 + 50 * ($0 - 1) })
            ],
            laps: [
                Lap(number: 1, start: 0, end: 1, isComplete: true), Lap(number: 2, start: 1, end: 3, isComplete: true),
            ])
        let warp = try #require(
            LapTimeWarp(
                lap: session.laps[1], in: session, sync: .identity, compared: session.laps[0], in: session,
                comparedSync: .identity))
        let composition = AVMutableComposition()
        let layer = try await CompositionBuilder.insertWarped(
            VideoInputSpec(url: fixture), warp: warp, duration: 3, into: composition)
        let track = try #require(composition.track(withTrackID: layer.trackID))
        func sourceTime(at seconds: Double) throws -> Double {
            let time = CMTime(seconds: seconds, preferredTimescale: 600)
            let mapping = try #require(track.segment(forTrackTime: time)).timeMapping
            let into = (time - mapping.target.start).seconds / mapping.target.duration.seconds
            return mapping.source.start.seconds + into * mapping.source.duration.seconds
        }
        // Halfway through lap 2 (2 s) the picture is halfway through lap 1 (0.5 s into the file).
        #expect(abs(try sourceTime(at: 2) - 0.5) < 0.01)
        #expect(abs(try sourceTime(at: 1.5) - 0.25) < 0.01)
        #expect(abs(try sourceTime(at: 2.9) - 0.95) < 0.01)
        // Nothing was pushed past the end of the project.
        #expect(track.timeRange.end.seconds <= 3.001)
    }
}
