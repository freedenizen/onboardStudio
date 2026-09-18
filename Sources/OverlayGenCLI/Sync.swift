import ArgumentParser
import Foundation
import Importers
import MediaKit
import ProjectModel
import TelemetryKit

struct Sync: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Find the offset between a video and a data file from motion (no clocks needed).")

    @Option(name: .long, help: "Video file.")
    var video: String

    @Option(name: .long, help: "Telemetry file (any supported format).")
    var data: String

    @Option(name: .long, help: "Seconds of video to analyse from --start-position.")
    var window: Double = 180

    @Option(name: .long, help: "Seconds into the video where analysis starts.")
    var startPosition: Double = 0

    @Option(name: .long, help: "Motion samples per second.")
    var rate: Double = 10

    @Option(name: .long, help: "Luma change that counts as motion in a thumbnail cell (0 = use the mean change).")
    var threshold: Double = 10

    @Flag(name: .long, help: "Print the result as JSON.")
    var json = false

    @Option(name: .long, help: "Write the two motion signals (video energy, log speed) to this CSV for inspection.")
    var dump: String?

    func run() async throws {
        let videoURL = URL(fileURLWithPath: video)
        let session = try FormatDetector.importSession(at: URL(fileURLWithPath: data))
        let info = try await MediaProbe.probe(videoURL)
        let options = MotionSync.Options(window: window, rate: rate, changeThreshold: threshold)
        let quiet = json
        let progress: @Sendable (Double) -> Void = { fraction in
            guard !quiet else { return }
            FileHandle.standardError.write(Data("\rAnalysing… \(Int(fraction * 100))%".utf8))
        }
        let videoSync = SyncSettings(startPositionInInput: startPosition)
        if let dump {
            let energy = try await MotionSync.motionEnergy(
                of: videoURL, start: startPosition, duration: min(window, info.duration - startPosition),
                options: options, progress: progress)
            guard let signal = MotionSync.motionSignal(of: session, rate: rate) else {
                throw ValidationError("The data file has neither speed nor g-force channels.")
            }
            var text = "kind,time,value\n"
            for (index, value) in energy.enumerated() {
                text += "energy,\(startPosition + Double(index) / rate),\(value)\n"
            }
            if let loudness = try await MotionSync.audioLoudness(of: videoURL, rate: rate) {
                for (index, value) in loudness.enumerated() { text += "audio,\(Double(index) / rate),\(value)\n" }
            }
            for (index, value) in signal.values.enumerated() {
                text += "\(signal.channel),\(signal.start + Double(index) / rate),\(value)\n"
            }
            try text.write(toFile: dump, atomically: true, encoding: .utf8)
            let suggestion = MotionSync.match(
                energy: energy, videoStart: startPosition, videoSync: videoSync, signal: signal, options: options)
            report(suggestion)
            return
        }
        let suggestion = try await MotionSync.suggest(
            video: videoURL, videoSync: videoSync, videoDuration: info.duration, data: session, options: options,
            progress: progress)
        if !json { FileHandle.standardError.write(Data("\r".utf8)) }
        report(suggestion)
    }

    func report(_ suggestion: MotionSync.Suggestion?) {
        guard let suggestion else {
            print("No motion pattern in the video matched the data.")
            return
        }
        if json {
            let object: [String: Any] = [
                "startPositionInInput": suggestion.sync.startPositionInInput, "offset": suggestion.offset,
                "score": suggestion.score, "prominence": suggestion.prominence, "channel": suggestion.channel,
                "source": suggestion.source,
                "convincing": suggestion.isConvincing,
            ]
            let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
            print(data.flatMap { String(bytes: $0, encoding: .utf8) } ?? "")
        } else {
            print("Data start position: \(String(format: "%.2f", suggestion.sync.startPositionInInput)) s")
            print("Offset (data − video): \(String(format: "%.2f", suggestion.offset)) s")
            print(
                "Match: \(suggestion.source) vs \(suggestion.channel), correlation "
                    + "\(String(format: "%.2f", suggestion.score)), "
                    + "prominence \(String(format: "%.2f", suggestion.prominence)) "
                    + (suggestion.isConvincing ? "(good)" : "(weak — verify in the sync wizard)"))
        }
    }
}
