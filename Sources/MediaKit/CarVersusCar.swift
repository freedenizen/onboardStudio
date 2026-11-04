import Foundation
import ProjectModel
import TelemetryKit

/// Two cars at one circuit, set against each other (#354): each car's best lap from the logbook,
/// read corner by corner the way two drivers' laps are, with a sentence per corner naming the car.
public struct CarVersusCar: Sendable {
    public struct Side: Sendable {
        public let car: String
        public let entry: LogbookEntry
        public let profile: LapProfile
    }

    public struct Trace: Identifiable, Sendable, Hashable {
        public var id: String { "\(car)-\(distance)" }
        public let car: String
        public let distance: Double
        public let speed: Double
    }

    public let first: Side
    public let second: Side
    /// `first`'s lap read against `second`'s, lined up by position.
    public let analysis: CoachingAnalysis
    public let units: CoachingUnits

    /// The two cars' best laps at a circuit, read in and compared; `nil` when either file is gone
    /// or has no complete lap. Slow: a file read each; call it off the main thread and keep it.
    public static func make(
        first: LogbookEntry, firstCar: String, second: LogbookEntry, secondCar: String, units: CoachingUnits = .metric
    ) -> CarVersusCar? {
        guard let sessionA = LogbookReferences.load(first), let sessionB = LogbookReferences.load(second),
            let lapA = LogbookReferences.profile(of: first, lap: first.bestLapNumber, session: sessionA),
            let lapB = LogbookReferences.profile(of: second, lap: second.bestLapNumber, session: sessionB),
            let analysis = CoachingAnalysis.analyse(
                lap: lapA, in: sessionA, reference: lapB, referencePhrase: "the \(secondCar)'s best lap",
                sameSession: false, units: units)
        else { return nil }
        return CarVersusCar(
            first: Side(car: firstCar, entry: first, profile: lapA),
            second: Side(car: secondCar, entry: second, profile: lapB), analysis: analysis, units: units)
    }

    /// Speed against distance for both laps, thinned to about `count` points each.
    public func speedTraces(count: Int = 400) -> [Trace] {
        func trace(_ side: Side) -> [Trace] {
            guard let speeds = side.profile.channels[.speed] else { return [] }
            let step = max(1, speeds.count / count)
            return stride(from: 0, to: speeds.count, by: step).map {
                Trace(car: side.car, distance: side.profile.distances[$0], speed: speeds[$0])
            }
        }
        return trace(first) + trace(second)
    }

    /// Who is quicker overall: "The GR86's best lap is 4.5 s quicker than the Miata's (1:52.40 to 1:56.90)."
    public var headline: String {
        let a = first.profile.duration
        let b = second.profile.duration
        let quicker = a < b ? first : second
        let slower = a < b ? second : first
        let gap = String(format: "%.1f", abs(a - b))
        let quickTime = TimeParsing.lapTimeString(quicker.profile.duration)
        let slowTime = TimeParsing.lapTimeString(slower.profile.duration)
        let times = "\(quickTime) to \(slowTime)"
        return "The \(quicker.car)'s best lap is \(gap) s quicker than the \(slower.car)'s (\(times))."
    }

    /// One sentence per corner, the quicker car first, in the coaching notes' words.
    public var sentences: [String] {
        let format = CoachingNotes.Formatter(units: units)
        return analysis.corners.map { corner in
            let lost = corner.timeLost
            let quicker = lost > 0 ? second.car : first.car
            let slower = lost > 0 ? first.car : second.car
            var parts: [String] = []
            if abs(lost) < 0.03 {
                parts.append("Turn \(corner.label): the two cars are level")
            } else {
                parts.append(
                    "Turn \(corner.label): the \(quicker) is \(format.seconds(abs(lost))) quicker than the \(slower)")
            }
            let fast = lost > 0 ? corner.reference : corner.lap
            let slow = lost > 0 ? corner.lap : corner.reference
            if let a = fast.brakePointMeters, let b = slow.brakePointMeters, abs(a - b) >= 3 {
                parts.append("brakes \(format.metres(abs(a - b))) \(a < b ? "later" : "earlier")")
            }
            let speed = fast.minimumSpeed - slow.minimumSpeed
            if abs(speed) >= 0.5 {
                parts.append("carries \(format.speed(abs(speed))) \(speed > 0 ? "more" : "less") through the apex")
            }
            let exit = fast.exitSpeed - slow.exitSpeed
            if abs(exit) >= 0.5 { parts.append("leaves \(format.speed(abs(exit))) \(exit > 0 ? "faster" : "slower")") }
            return parts.count > 1 ? parts[0] + ": " + parts.dropFirst().joined(separator: ", ") + "." : parts[0] + "."
        }
    }
}
