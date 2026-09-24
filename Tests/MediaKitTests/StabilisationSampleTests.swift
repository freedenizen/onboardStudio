import AVFoundation
import Foundation
import ProjectModel
import Testing
import Vision

@testable import MediaKit

/// The user's HERO13 helmet clip (local only): steadied from its motion record, the exported picture
/// moves less from frame to frame than the recording did (#262).
@Suite("Stabilisation on real footage", .serialized)
struct StabilisationSampleTests {
    @Test func aSteadiedExportShakesLessThanTheRecording() async throws {
        guard let dir = ProcessInfo.processInfo.environment["ONBOARD_SAMPLES_DIR"] else { return }
        let clip = URL(fileURLWithPath: dir).appending(path: "GX010037.MP4")
        guard FileManager.default.fileExists(atPath: clip.path) else { return }
        var shake: [Bool: Double] = [:]
        for steadied in [false, true] {
            var settings = VideoInputSettings()
            if steadied { settings.stabilisation = StabilisationSettings(method: .motionData) }
            let video = Input(label: "GoPro", source: MediaReference(path: clip.path), kind: .video(settings))
            var project = Project(
                inputs: [video],
                displayObjects: [
                    DisplayObject(label: "v", inputID: video.id, frame: .full, kind: .video(VideoObjectParams()))
                ])
            project.settings.outputWidth = 640
            project.settings.outputHeight = 480
            let loaded = try await ProjectCompiler.load(
                project, location: ProjectLocation(URL(fileURLWithPath: "/tmp/x.onboardproj")))
            #expect(steadied == (loaded.orientations[video.id] != nil))
            let compiled = try await ProjectCompiler.compile(loaded)
            let output = MediaFixtures.temporaryOutput(steadied ? "steady" : "shaky")
            defer { try? FileManager.default.removeItem(at: output) }
            var export = ExportSettings(width: 640, height: 480, frameRate: 30, videoBitrate: 4_000_000)
            export.audioBitrate = nil
            for try await _ in Exporter.export(compiled, settings: export, range: 300...302, to: output) {}
            shake[steadied] = try await Self.meanShift(of: output)
        }
        let before = try #require(shake[false])
        let after = try #require(shake[true])
        #expect(after < before * 0.7, "shake \(before) → \(after) px per frame")
    }

    /// Mean frame-to-frame shift of the picture's centre, from Vision homographies.
    static func meanShift(of url: URL) async throws -> Double {
        let asset = AVURLAsset(url: url)
        let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(
            track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        reader.add(output)
        reader.startReading()
        var previous: CVPixelBuffer?
        var total = 0.0
        var count = 0
        while let sample = output.copyNextSampleBuffer() {
            guard let buffer = CMSampleBufferGetImageBuffer(sample) else { continue }
            if let previous {
                let request = VNHomographicImageRegistrationRequest(targetedCVPixelBuffer: buffer)
                try VNImageRequestHandler(cvPixelBuffer: previous).perform([request])
                if let m = request.results?.first?.warpTransform {
                    let c = simd_float3(
                        Float(CVPixelBufferGetWidth(buffer)) / 2, Float(CVPixelBufferGetHeight(buffer)) / 2, 1)
                    let p = m * c
                    let dx = Double(p.x / p.z - c.x)
                    let dy = Double(p.y / p.z - c.y)
                    total += (dx * dx + dy * dy).squareRoot()
                    count += 1
                }
            }
            previous = buffer
        }
        return count > 0 ? total / Double(count) : 0
    }
}
