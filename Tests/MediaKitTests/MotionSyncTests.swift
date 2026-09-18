import AVFoundation
import Foundation
import Testing

@testable import Importers
@testable import MediaKit
@testable import ProjectModel
@testable import RenderKit
@testable import TelemetryKit

/// Writes a short H.264 clip in which a bar sweeps across the frame only during `moving`
/// intervals (video seconds); the rest of the time the picture is static.
enum SyntheticMotionClip {
    static func write(duration: Double, fps: Int = 30, moving: [ClosedRange<Double>]) async throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "motion-\(UUID().uuidString).mp4")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let width = 320
        let height = 180
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
            ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: PixelBuffers.pixelFormat])
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? MotionSync.MotionError.noVideoTrack }
        writer.startSession(atSourceTime: .zero)
        let frames = Int(duration * Double(fps))
        var position = 0.0
        for index in 0..<frames {
            let t = Double(index) / Double(fps)
            if moving.contains(where: { $0.contains(t) }) { position += 6 }
            let buffer = try PixelBuffers.makeBuffer(width: width, height: height)
            try PixelBuffers.draw(into: buffer) { cg, size in
                cg.setFillColor(PixelBuffers.color(red: 0.2, green: 0.3, blue: 0.4))
                cg.fill(CGRect(origin: .zero, size: size))
                cg.setFillColor(PixelBuffers.color(red: 1, green: 1, blue: 1))
                let x = position.truncatingRemainder(dividingBy: Double(width))
                cg.fill(CGRect(x: x, y: 40, width: 30, height: 100))
                cg.fill(CGRect(x: x - Double(width), y: 40, width: 30, height: 100))
            }
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(index), timescale: CMTimeScale(fps)))
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? MotionSync.MotionError.noVideoTrack }
        return url
    }
}

@Suite("Motion sync", .serialized)
struct MotionSyncTests {
    static func speedSession(duration: Double, moving: [ClosedRange<Double>], shift: Double) -> TelemetrySession {
        let times = Array(stride(from: 0.0, through: duration, by: 0.1))
        let speeds = times.map { t -> Double in
            let v = t - shift
            return moving.contains { $0.contains(v) } ? 25 : 0
        }
        return TelemetrySession(
            info: SessionInfo(sourceFormat: "test"),
            channels: [Channel(role: .speed, name: "Speed", unit: .metersPerSecond, times: times, values: speeds)],
            laps: [])
    }

    @Test func findsTheOffsetBetweenASyntheticClipAndALog() async throws {
        let moving: [ClosedRange<Double>] = [3...5, 9...12, 15...16, 22...23.5]
        let clip = try await SyntheticMotionClip.write(duration: 28, moving: moving)
        defer { try? FileManager.default.removeItem(at: clip) }
        // The log starts 41.3 s before the video and runs for two minutes.
        let session = Self.speedSession(duration: 120, moving: moving, shift: 41.3)
        let suggestion = try #require(
            try await MotionSync.suggest(
                video: clip, videoSync: SyncSettings(offsetInProject: 0.5), videoDuration: 28, data: session,
                options: MotionSync.Options(window: 60, rate: 10)))
        #expect(abs(suggestion.offset - 41.3) < 0.25, "offset \(suggestion.offset)")
        #expect(abs(suggestion.sync.startPositionInInput - 41.3) < 0.25)
        #expect(suggestion.sync.offsetInProject == 0.5)
        #expect(suggestion.channel == "speed")
        #expect(suggestion.isConvincing, "score \(suggestion.score) prominence \(suggestion.prominence)")
    }

    @Test func honoursTheVideoStartPosition() throws {
        // Energy sampled from video second 10; the log's motion starts 3 s into the session.
        let rate = 10.0
        let energy = (0..<300).map { i in (5..<15).contains(i / 10) ? 1.0 : 0.0 }
        let values = (0..<1200).map { i in (80..<180).contains(i / 10) ? 25.0 : 0.0 }
        let suggestion = try #require(
            MotionSync.match(
                energy: energy, videoStart: 10, videoSync: .identity,
                signal: MotionSync.MotionSignal(start: 3, values: values, channel: "speed"),
                options: MotionSync.Options(rate: rate)))
        // Video second 15 (energy sample 50) ↔ session second 3 + 80 = 83 → session = video + 68.
        // Half a second of smoothing shifts a hard step slightly; a lap sync is fine to 0.5 s.
        #expect(abs(suggestion.offset - 68) < 0.5, "offset \(suggestion.offset)")
        #expect(abs(suggestion.sync.startPositionInInput - 78) < 0.5)
    }

    @Test func gForceIsTheFallbackChannel() throws {
        let times = Array(stride(from: 0.0, through: 10.0, by: 0.1))
        let session = TelemetrySession(
            info: SessionInfo(sourceFormat: "test"),
            channels: [
                Channel(role: .lateralG, name: "lat", unit: .gForce, times: times, values: times.map { sin($0) }),
                Channel(role: .longitudinalG, name: "lon", unit: .gForce, times: times, values: times.map { cos($0) }),
            ], laps: [])
        let signal = try #require(MotionSync.motionSignal(of: session, rate: 10))
        #expect(signal.channel == "g-force")
        #expect(signal.values.allSatisfy { abs($0 - 1) < 0.01 })
        #expect(
            MotionSync.motionSignal(
                of: TelemetrySession(info: SessionInfo(sourceFormat: "x"), channels: [], laps: []), rate: 10) == nil)
    }
}

@Suite("Motion sync on real samples")
struct RealMotionSyncTests {
    /// The HERO13 clip against the RaceChrono log recorded in the same car; the GPS cross-check
    /// in M10 established data time 1787528146.8 at video time 0.
    @Test func audioLoudnessFindsTheGPSVerifiedOffset() async throws {
        guard let dir = ProcessInfo.processInfo.environment["OVERLAYGEN_SAMPLES_DIR"] else { return }
        let video = URL(fileURLWithPath: dir).appending(path: "GX010037.MP4")
        let data = URL(fileURLWithPath: dir).appending(path: "session_20260823_163604_sonoma_v3.csv")
        guard FileManager.default.fileExists(atPath: video.path), FileManager.default.fileExists(atPath: data.path)
        else { return }
        let session = try FormatDetector.importSession(at: data)
        let info = try await MediaProbe.probe(video)
        let suggestion = try #require(
            try await MotionSync.suggest(
                video: video, videoSync: .identity, videoDuration: info.duration, data: session))
        #expect(suggestion.source == "audio loudness")
        #expect(
            abs(suggestion.sync.startPositionInInput - 1_787_528_146.8) < 3,
            "start \(suggestion.sync.startPositionInInput)")
        #expect(suggestion.isConvincing, "score \(suggestion.score) prominence \(suggestion.prominence)")
    }
}
