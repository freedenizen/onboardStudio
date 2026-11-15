import ArgumentParser
import Foundation
import MediaKit

/// `onboard traffic GX010037.MP4 …` (#573): reads onboard videos for a car close ahead, one
/// keyframe a second, and lists the stretches of each file where there was one. The reading is
/// kept, as the app keeps it, so `onboard coach --detect-traffic` and the Coaching window find it.
struct TrafficCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "traffic",
        abstract: "Read onboard videos for a car close ahead, one keyframe a second.")

    @Argument(help: "Video files, read in turn.")
    var paths: [String]

    @Flag(name: .long, help: "Read the files again even when they have been read before.")
    var again = false

    func run() async throws {
        for path in paths {
            let url = URL(fileURLWithPath: path)
            let started = Date()
            var sightings = again ? nil : VideoTraffic.saved(for: url)
            let cached = sightings != nil
            if sightings == nil {
                for try await (_, result) in VideoTraffic.analyse(url) where result != nil { sightings = result }
            }
            guard let sightings else { throw ValidationError("'\(path)' could not be read.") }
            let took = cached ? "read before" : String(format: "read in %.1f s", Date().timeIntervalSince(started))
            print("\(url.lastPathComponent): \(sightings.times.count) pictures, \(took)")
            let stretches = Self.stretches(sightings)
            if stretches.isEmpty { print("  No car close ahead.") }
            for stretch in stretches {
                print(String(format: "  Car close ahead %.0f–%.0f s", stretch.lowerBound, stretch.upperBound))
            }
        }
    }

    /// The runs of pictures with a car ahead, two or more in a row, in the file's seconds.
    static func stretches(_ sightings: CarSightings) -> [ClosedRange<Double>] {
        var result: [ClosedRange<Double>] = []
        var start: Int?
        for index in 0...sightings.widths.count {
            let seen = index < sightings.widths.count && sightings.widths[index] > 0
            if seen, start == nil { start = index }
            if !seen, let first = start {
                if index - first >= 2 { result.append(sightings.times[first]...sightings.times[index - 1]) }
                start = nil
            }
        }
        return result
    }
}
